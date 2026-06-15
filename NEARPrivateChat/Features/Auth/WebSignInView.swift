import SwiftUI
import WebKit

/// In-app web sign-in that loads the real private.near.ai auth route, lets the
/// user authenticate with whatever method works for them (NEAR wallet, Google,
/// GitHub), and then adopts the session the web app issues.
///
/// Why this exists: the hosted web app already owns the complete session-login
/// UX, provider choices, cookies, and redirect handling. The native app keeps
/// users on that same surface inside a WKWebView, then reads back the session
/// token the web client stores in `localStorage` (`sessionToken`/`sessionId`,
/// plain strings — verified against the production bundle). The user's own
/// session stays on the user's device.
struct WebSignInView: View {
    let url: URL
    /// Called with the harvested session once the web login lands a session.
    /// The presenter adopts it via `SessionStore.adoptSession`.
    let onHarvest: (_ session: AuthSession) -> Void
    let onCancel: () -> Void

    @State private var isLoading = true
    @State private var didHarvest = false
    @State private var showsHarvestHelp = false
    @State private var reloadID = UUID()

    init(
        url: URL = Self.loginURL,
        onHarvest: @escaping (_ session: AuthSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.url = url
        self.onHarvest = onHarvest
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthWebView(
                    url: url,
                    onTokenHarvested: { session in
                        guard !didHarvest else { return }
                        didHarvest = true
                        onHarvest(session)
                    },
                    onLoadingChanged: { isLoading = $0 }
                )
                .id(reloadID)
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Loading sign-in")
                }

                if showsHarvestHelp && !didHarvest {
                    VStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Still waiting for the sign-in page to return a session. Finish sign-in above, retry, or use More ways to sign in > Session token if private.near.ai already shows you signed in.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                showsHarvestHelp = false
                                isLoading = true
                                reloadID = UUID()
                            } label: {
                                Label("Retry web sign-in", systemImage: "arrow.clockwise")
                                    .font(.footnote.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityIdentifier("auth.retryWebSignIn")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle.app(AppRadius.pill))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .accessibilityIdentifier("auth.webHarvestHelp")
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Sign in")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .accessibilityHint("Closes web sign-in and returns to other sign-in methods.")
                        .accessibilityIdentifier("auth.cancelWebSignIn")
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 24_000_000_000)
                guard !Task.isCancelled, !didHarvest else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    showsHarvestHelp = true
                }
            }
        }
    }

    /// The hosted auth shell is the provider chooser. Specific provider rows
    /// below can start at a deeper route, but the default should not force NEAR
    /// wallet when the user only tapped "Sign in."
    nonisolated static let loginURL = validatedURL("https://private.near.ai/auth")
    nonisolated static let hostedCallbackURL = validatedURL("https://private.near.ai/auth/callback")

    nonisolated static func hostedSignInURL(for provider: OAuthProvider) -> URL {
        switch provider {
        case .near:
            return hostedURL(
                path: "/near-login",
                queryItems: [
                    URLQueryItem(name: "frontend_callback", value: hostedCallbackURL.absoluteString)
                ]
            )
        case .google, .github:
            return hostedURL(
                path: "/v1/auth/\(provider.rawValue)",
                queryItems: [
                    URLQueryItem(name: "frontend_callback", value: hostedCallbackURL.absoluteString)
                ]
            )
        }
    }

    nonisolated static func isHostedAuthStrandedURL(_ url: URL) -> Bool {
        guard isPrivateChatHostedURL(url) else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return path == "/" || path == "/welcome" || path == "/auth/mobile"
    }

    nonisolated static func hostedAuthReloadURL(for url: URL) -> URL? {
        isHostedAuthStrandedURL(url) ? loginURL : nil
    }

    nonisolated private static func validatedURL(_ rawValue: String) -> URL {
        guard let url = URL(string: rawValue) else {
            assertionFailure("Invalid web sign-in URL: \(rawValue)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    nonisolated private static func hostedURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "private.near.ai"
        components.path = path
        components.queryItems = queryItems
        return components.url ?? loginURL
    }

    nonisolated fileprivate static func isPrivateChatHostedURL(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "private.near.ai" || host.hasSuffix(".private.near.ai")
    }

    nonisolated static func sessionFromCallbackURL(_ url: URL) -> AuthSession? {
        guard isTrustedCallbackURL(url) else { return nil }
        let values = callbackValues(from: url)
        guard let token = firstNonEmptyValue(
            named: [
                "token",
                "session_token",
                "sessionToken",
                "auth_token",
                "authToken",
                "access_token",
                "accessToken"
            ],
            in: values
        ) else {
            return nil
        }

        return AuthSession(
            token: token,
            sessionID: firstNonEmptyValue(named: ["session_id", "sessionID", "sessionId"], in: values) ?? "",
            expiresAt: firstNonEmptyValue(named: ["expires_at", "expiresAt"], in: values),
            isNewUser: boolValue(named: ["is_new_user", "isNewUser"], in: values) ?? false
        )
    }

    nonisolated private static func isTrustedCallbackURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "nearai" || scheme == "nearprivatechat" {
            return url.host?.lowercased() == "auth" && url.path.isEmpty
        }

        guard scheme == "https",
              url.host?.lowercased() == "private.near.ai" else {
            return false
        }

        let path = url.path.isEmpty ? "/" : url.path
        return path == "/auth" || path == "/auth/callback" || path.hasPrefix("/auth/")
    }

    nonisolated private static func callbackValues(from url: URL) -> [String: [String]] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var values: [String: [String]] = [:]
        append(components.queryItems, to: &values)
        if let fragment = components.fragment,
           let fragmentComponents = URLComponents(string: "nearai://auth?\(fragment)") {
            append(fragmentComponents.queryItems, to: &values)
        }
        return values
    }

    nonisolated private static func append(_ queryItems: [URLQueryItem]?, to values: inout [String: [String]]) {
        for item in queryItems ?? [] {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            values[name, default: []].append(item.value ?? "")
        }
    }

    nonisolated private static func firstNonEmptyValue(named names: [String], in values: [String: [String]]) -> String? {
        for name in names {
            if let value = values[name]?
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return value
            }
        }
        return nil
    }

    nonisolated private static func boolValue(named names: [String], in values: [String: [String]]) -> Bool? {
        guard let rawValue = firstNonEmptyValue(named: names, in: values)?.lowercased() else { return nil }
        switch rawValue {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}

/// UIKit bridge hosting the WKWebView. A repeating poll reads the auth token
/// out of `localStorage`; sign-in completion is a SPA route change that may not
/// fire a navigation callback, so polling is the reliable signal.
private struct AuthWebView: UIViewRepresentable {
    let url: URL
    let onTokenHarvested: (_ session: AuthSession) -> Void
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
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

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
        coordinator.dismissPopupWebView()
        coordinator.stopPolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onTokenHarvested: (_ session: AuthSession) -> Void
        private let onLoadingChanged: (Bool) -> Void
        weak var webView: WKWebView?
        private weak var popupWebView: WKWebView?
        private var pollTimer: Timer?
        private var finished = false

        // Reads both values in one round-trip; returns a JSON string the native
        // side decodes. Only the private.near.ai origin holds these keys.
        private static let harvestScript = """
        JSON.stringify({
          token: localStorage.getItem('sessionToken') || localStorage.getItem('session_token') || localStorage.getItem('auth_token') || localStorage.getItem('access_token'),
          sessionId: localStorage.getItem('sessionId') || localStorage.getItem('session_id')
        })
        """
        init(
            onTokenHarvested: @escaping (_ session: AuthSession) -> Void,
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
            if let url = webView.url,
               let session = WebSignInView.sessionFromCallbackURL(url) {
                finish(with: session)
                return
            }
            // Only evaluate on the private.near.ai origin; the wallet/Google
            // pages have their own (irrelevant) localStorage.
            guard WebSignInView.isPrivateChatHostedURL(webView.url) else { return }
            webView.evaluateJavaScript(Self.harvestScript) { [weak self, weak webView] result, _ in
                guard let self,
                      !self.handleHarvestResult(result),
                      !self.finished,
                      let webView else {
                    return
                }
                self.reloadHostedAuthIfStranded(on: webView)
            }
        }

        private func reloadHostedAuthIfStranded(on webView: WKWebView) {
            guard !finished,
                  let url = webView.url,
                  let reloadURL = WebSignInView.hostedAuthReloadURL(for: url) else {
                return
            }
            webView.load(URLRequest(url: reloadURL))
        }

        @discardableResult
        private func handleHarvestResult(_ result: Any?) -> Bool {
            guard !finished,
                  let json = result as? String,
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(HarvestResult.self, from: data),
                  let token = parsed.token, !token.isEmpty else {
                return false
            }
            finish(
                with: AuthSession(
                    token: token,
                    sessionID: parsed.sessionId ?? "",
                    expiresAt: nil,
                    isNewUser: false
                )
            )
            return true
        }

        private func finish(with session: AuthSession) {
            guard !finished else { return }
            finished = true
            dismissPopupWebView()
            stopPolling()
            onTokenHarvested(session)
        }

        func dismissPopupWebView() {
            popupWebView?.navigationDelegate = nil
            popupWebView?.uiDelegate = nil
            popupWebView?.removeFromSuperview()
            popupWebView = nil
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
            if let url = navigationAction.request.url,
               let session = WebSignInView.sessionFromCallbackURL(url) {
                finish(with: session)
                decisionHandler(.cancel)
                return
            }

            if let url = navigationAction.request.url,
               let reloadURL = WebSignInView.hostedAuthReloadURL(for: url) {
                webView.load(URLRequest(url: reloadURL))
                decisionHandler(.cancel)
                return
            }

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
        // (target=_blank / window.open). Return a real child WKWebView so
        // wallet pages that rely on `window.opener` can receive connection
        // details from the original private.near.ai page. Flattening the popup
        // into the main web view strands NEAR wallet pages on "Receiving
        // connection details..." with no session token to harvest.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            dismissPopupWebView()

            configuration.websiteDataStore = .default()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.allowsBackForwardNavigationGestures = true
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            popup.backgroundColor = .systemBackground
            webView.addSubview(popup)
            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView === popupWebView {
                dismissPopupWebView()
            }
        }
    }
}


// MARK: - NEAR AI Cloud web sign-in (key harvest, no manual paste)


/// In-app web sign-in for NEAR AI Cloud. Loads cloud-api.near.ai's hosted login
/// (Google / GitHub / NEAR), lets the user authenticate, and then harvests the
/// `sk-` API key the authenticated cloud dashboard exposes — so the user never
/// has to copy/paste a key.
///
/// Unlike `WebSignInView` (private.near.ai stores the session token in
/// localStorage), cloud-api lands a cookie session and the key surfaces on the
/// dashboard. We therefore scan both web storage and the visible page for an
/// `sk-` token, on the cloud-api / agent.near.ai origins only. The scan also
/// reports what storage keys exist when no key is found, so the harvest target
/// can be tuned against the live flow.
struct CloudWebSignInView: View {
    /// Called with the harvested `sk-` key once the cloud login exposes one.
    let onHarvest: (_ apiKey: String) -> Void
    let onCancel: () -> Void

    @State private var isLoading = true
    @State private var didHarvest = false
    @State private var showsHelp = false
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                CloudAuthWebView(
                    url: Self.loginURL,
                    onKeyHarvested: { key in
                        guard !didHarvest else { return }
                        didHarvest = true
                        onHarvest(key)
                    },
                    onLoadingChanged: { isLoading = $0 }
                )
                .id(reloadID)
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Loading NEAR AI Cloud sign-in")
                }

                if showsHelp && !didHarvest {
                    VStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Finish signing in above. Once you reach your NEAR AI Cloud dashboard and a key is shown (create one if prompted), it connects automatically.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                showsHelp = false
                                isLoading = true
                                reloadID = UUID()
                            } label: {
                                Label("Reload sign-in", systemImage: "arrow.clockwise")
                                    .font(.footnote.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityIdentifier("cloudAuth.reload")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle.app(AppRadius.pill))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Connect NEAR AI Cloud")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("cloudAuth.cancel")
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, !didHarvest else { return }
                withAnimation(.easeOut(duration: 0.2)) { showsHelp = true }
            }
        }
    }

    /// The hosted cloud login (provider chooser: Google / GitHub).
    nonisolated static let loginURL = validatedURL("https://cloud-api.near.ai/v1/auth/login")

    nonisolated private static func validatedURL(_ rawValue: String) -> URL {
        guard let url = URL(string: rawValue) else {
            assertionFailure("Invalid cloud sign-in URL: \(rawValue)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    /// Hosts whose pages we scan for the key. OAuth provider pages (Google /
    /// GitHub) are never scanned.
    nonisolated static func isCloudHarvestHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "cloud-api.near.ai"
            || host == "agent.near.ai"
            || host.hasSuffix(".near.ai") && host.contains("cloud")
    }

    /// Validates a candidate harvested string as a NEAR AI Cloud key.
    nonisolated static func isLikelyCloudKey(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        guard value.hasPrefix("sk-"), value.count >= 16 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.dropFirst(3).unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// UIKit bridge hosting the WKWebView for the cloud sign-in. Polls the page for
/// an `sk-` key (web storage + visible DOM) once the user reaches a cloud-api /
/// dashboard origin.
private struct CloudAuthWebView: UIViewRepresentable {
    let url: URL
    let onKeyHarvested: (_ apiKey: String) -> Void
    let onLoadingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyHarvested: onKeyHarvested, onLoadingChanged: onLoadingChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Persistent store so the OAuth cookies survive the provider redirect hops.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

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
        coordinator.dismissPopupWebView()
        coordinator.stopPolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onKeyHarvested: (_ apiKey: String) -> Void
        private let onLoadingChanged: (Bool) -> Void
        weak var webView: WKWebView?
        private weak var popupWebView: WKWebView?
        private var pollTimer: Timer?
        private var finished = false

        // Scans web storage + visible DOM for an `sk-` key. When none is found it
        // reports the origin and storage keys so the harvest target can be tuned.
        private static let harvestScript = """
        (function () {
          function scanStore(store) {
            try {
              for (var i = 0; i < store.length; i++) {
                var v = store.getItem(store.key(i));
                if (v && /^sk-[A-Za-z0-9_\\-]{16,}$/.test(v.trim())) return v.trim();
              }
            } catch (e) {}
            return null;
          }
          var k = scanStore(window.localStorage) || scanStore(window.sessionStorage);
          if (k) return JSON.stringify({ key: k, src: 'storage' });
          var text = document.body ? document.body.innerText : '';
          var m = text.match(/sk-[A-Za-z0-9_\\-]{20,}/);
          if (m) return JSON.stringify({ key: m[0], src: 'dom' });
          var ls = [];
          try { for (var j = 0; j < window.localStorage.length; j++) ls.push(window.localStorage.key(j)); } catch (e) {}
          return JSON.stringify({ key: null, host: location.host, path: location.pathname, lskeys: ls });
        })()
        """

        init(
            onKeyHarvested: @escaping (_ apiKey: String) -> Void,
            onLoadingChanged: @escaping (Bool) -> Void
        ) {
            self.onKeyHarvested = onKeyHarvested
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
            // Only scan on cloud-api / dashboard origins; provider pages are skipped.
            guard CloudWebSignInView.isCloudHarvestHost(webView.url) else { return }
            webView.evaluateJavaScript(Self.harvestScript) { [weak self] result, _ in
                guard let self, !self.finished, let json = result as? String else { return }
                self.handleHarvestResult(json)
            }
        }

        private func handleHarvestResult(_ json: String) {
            guard let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(HarvestResult.self, from: data) else {
                return
            }
            if CloudWebSignInView.isLikelyCloudKey(parsed.key) {
                #if DEBUG
                NSLog("[NPC-debug] cloud sign-in: harvested key via \(parsed.src ?? "?")")
                #endif
                finish(with: parsed.key!.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            #if DEBUG
            NSLog("[NPC-debug] cloud sign-in: no key yet host=\(parsed.host ?? "?") path=\(parsed.path ?? "?") lskeys=\(parsed.lskeys ?? [])")
            #endif
        }

        private func finish(with key: String) {
            guard !finished else { return }
            finished = true
            dismissPopupWebView()
            stopPolling()
            onKeyHarvested(key)
        }

        func dismissPopupWebView() {
            popupWebView?.navigationDelegate = nil
            popupWebView?.uiDelegate = nil
            popupWebView?.removeFromSuperview()
            popupWebView = nil
        }

        private struct HarvestResult: Decodable {
            let key: String?
            let src: String?
            let host: String?
            let path: String?
            let lskeys: [String]?
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
            // Hand native app deep links (some wallets) to the system.
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

        // MARK: WKUIDelegate — OAuth providers often open a popup (window.open).

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            dismissPopupWebView()

            configuration.websiteDataStore = .default()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.allowsBackForwardNavigationGestures = true
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            popup.backgroundColor = .systemBackground
            webView.addSubview(popup)
            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView === popupWebView {
                dismissPopupWebView()
            }
        }
    }
}
