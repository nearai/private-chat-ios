import SwiftUI
import WebKit

struct KaTeXWebView: UIViewRepresentable {
    let formula: String
    let displayMode: Bool
    @Binding var preferredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(preferredHeight: $preferredHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "heightHandler")

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        let html = buildHTML(formula: formula, displayMode: displayMode)
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No dynamic updates needed; formula is immutable per view lifetime.
    }

    // MARK: - HTML builder

    private func buildHTML(formula: String, displayMode: Bool) -> String {
        // Escape backticks so the JS String.raw`` template literal is safe.
        let escaped = formula
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let displayModeJS = displayMode ? "true" : "false"

        // Font color adapts via CSS prefers-color-scheme so it matches the
        // chat bubble in both light and dark mode.
        return """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.js"></script>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: transparent; }
  body { padding: 4px 2px; }
  @media (prefers-color-scheme: dark) {
    .katex { color: #e8e8f0; }
  }
  @media (prefers-color-scheme: light) {
    .katex { color: #1a1a2e; }
  }
</style>
</head>
<body>
<div id="m"></div>
<script>
try {
  katex.render(String.raw`\(escaped)`, document.getElementById("m"), {
    displayMode: \(displayModeJS),
    throwOnError: false
  });
} catch(e) {
  document.getElementById("m").textContent = String.raw`\(escaped)`;
}
// Measure and report height after a brief layout pass.
function reportHeight() {
  var h = document.body.scrollHeight;
  window.webkit.messageHandlers.heightHandler.postMessage(h);
}
if (document.readyState === "complete") {
  reportHeight();
} else {
  window.addEventListener("load", reportHeight);
}
</script>
</body>
</html>
"""
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        @Binding var preferredHeight: CGFloat

        init(preferredHeight: Binding<CGFloat>) {
            _preferredHeight = preferredHeight
        }

        // Called by the JS heightHandler message.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "heightHandler",
                  let value = message.body as? CGFloat,
                  value > 0 else { return }
            DispatchQueue.main.async {
                self.preferredHeight = value
            }
        }

        // Fallback: measure after page load completes.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.preferredHeight = height
                    }
                }
            }
        }
    }
}
