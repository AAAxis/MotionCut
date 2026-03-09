import SwiftUI
import WebKit

struct AuthWebView: UIViewRepresentable {
    let url: URL
    let onTokenReceived: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTokenReceived: onTokenReceived)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onTokenReceived: (String) -> Void

        init(onTokenReceived: @escaping (String) -> Void) {
            self.onTokenReceived = onTokenReceived
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                onTokenReceived(token)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
