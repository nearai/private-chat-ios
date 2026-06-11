import SwiftUI
import WebKit

/// In-app web sign-in that loads the real private.near.ai login, lets the user
/// authenticate with whatever method works for them (NEAR wallet, Google,
/// GitHub), and then adopts the session the web app issues.
///
/// Why this exists: the hosted OAuth/redirect flows can't complete on device —
/// the backend only allowlists `https://private.near.ai` callbacks, not the
/// app's `nearai://` scheme, and the NEAR-wallet web flow never redirects its
/// token back to a native callback at all. Rather than fight the redirect, we
/// run the genuine web login inside a WKWebView and read back the session token
/// the web client stores in `localStorage` (`sessionToken`/`sessionId`, plain
/// strings — verified against the production bundle). The user's own session,
/// on the user's device; no backend change required.
struct WebSignInView: View {
    /// Called with the harvested `{token, sessionID}` once the web login lands a
    /// session. The presenter adopts it via `SessionStore.adoptSession`.
    let onHarvest: (_ token: String, _ sessionID: String) -> Void
    let onCancel: () -> Void

    @State private var isLoading = true
    @State private var didHarvest = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuthWebView(
                    url: Self.loginURL,
                    onTokenHarvested: { token, sessionID in
                        guard !didHarvest else { return }
                        didHarvest = true
                        onHarvest(token, sessionID)
                    },
                    onLoadingChanged: { isLoading = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("Sign in")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    private static let loginURL = URL(string: "https://private.near.ai/")!
}

/// UIKit bridge hosting the WKWebView. A repeating poll reads the auth token
/// out of `localStorage`; sign-in completion is a SPA route change that may not
/// fire a navigation callback, so polling is the reliable signal.
private struct AuthWebView: UIViewRepresentable {
    let url: URL
    let onTokenHarvested: (_ token: String, _ sessionID: String) -> Void
    let onLoadingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTokenHarvested: onTokenHarvested, onLoadingChanged: onLoadingChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Persistent data store so the wallet/Google cookies set mid-flow
        // survive the OAuth redirect hops back to private.near.ai.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        context.coordinator.startPolling()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onTokenHarvested: (_ token: String, _ sessionID: String) -> Void
        private let onLoadingChanged: (Bool) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?
        private var finished = false

        // Reads both values in one round-trip; returns a JSON string the native
        // side decodes. Only the private.near.ai origin holds these keys.
        private static let harvestScript = """
        JSON.stringify({token: localStorage.getItem('sessionToken'), sessionId: localStorage.getItem('sessionId')})
        """

        init(
            onTokenHarvested: @escaping (_ token: String, _ sessionID: String) -> Void,
            onLoadingChanged: @escaping (Bool) -> Void
        ) {
            self.onTokenHarvested = onTokenHarvested
            self.onLoadingChanged = onLoadingChanged
        }

        func startPolling() {
            stopPolling()
            let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
                self?.harvestIfReady()
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        private func harvestIfReady() {
            guard !finished, let webView else { return }
            // Only evaluate on the private.near.ai origin; the wallet/Google
            // pages have their own (irrelevant) localStorage.
            guard let host = webView.url?.host, host.hasSuffix("private.near.ai") else { return }
            webView.evaluateJavaScript(Self.harvestScript) { [weak self] result, _ in
                guard let self, let json = result as? String,
                      let data = json.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(HarvestResult.self, from: data),
                      let token = parsed.token, !token.isEmpty else { return }
                self.finished = true
                self.stopPolling()
                self.onTokenHarvested(token, parsed.sessionId ?? "")
            }
        }

        private struct HarvestResult: Decodable {
            let token: String?
            let sessionId: String?
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
            harvestIfReady()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Native NEAR wallets and some providers are reached via non-http
            // schemes (app deep links). Hand those to the system rather than
            // failing inside the web view.
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about" {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: WKUIDelegate

        // Wallet-selector and OAuth often open the next step in a popup
        // (target=_blank / window.open). Load it in the same web view so the
        // flow stays in one place and returns to private.near.ai.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
