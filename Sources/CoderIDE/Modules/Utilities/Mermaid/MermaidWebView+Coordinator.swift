import AppKit
import Foundation
import WebKit

extension MermaidWebView.Coordinator {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mermaidImageBridge", let body = message.body as? [String: Any] else { return }
        guard let type = body["type"] as? String else { return }
        let payload = body["payload"] as? String

        switch type {
        case "rendered":
            if let payload = payload {
                Task { @MainActor in self.onImageRendered?(payload) }
            }
        case "renderedPNG":
            if let payload = payload, payload.hasPrefix("data:image/png;base64,") {
                let base64 = String(payload.dropFirst("data:image/png;base64,".count))
                if let pngData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    Task { @MainActor in self.onImageRenderedPNG?(pngData) }
                }
            }
        case "height":
            if let payload = payload, let h = Double(payload) {
                Task { @MainActor in self.onHeightChanged?(CGFloat(h)) }
            }
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
