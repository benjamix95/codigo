import SwiftUI
import WebKit
import AppKit

// MARK: - Mermaid WebView

struct MermaidWebView: NSViewRepresentable {
    let mermaidCode: String
    let accentColor: Color
    let isDarkMode: Bool
    let onImageRendered: ((String) -> Void)?
    let onImageRenderedPNG: ((Data) -> Void)?
    let onHeightChanged: ((CGFloat) -> Void)?
    let onError: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "mermaidImageBridge")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "javaScriptEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        loadMermaid(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedCode != mermaidCode
            || context.coordinator.lastRenderedDarkMode != isDarkMode {
            context.coordinator.lastRenderedCode = mermaidCode
            context.coordinator.lastRenderedDarkMode = isDarkMode
            loadMermaid(webView: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaidImageBridge")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImageRendered: onImageRendered,
            onImageRenderedPNG: onImageRenderedPNG,
            onHeightChanged: onHeightChanged,
            onError: onError
        )
    }

    private func loadMermaid(webView: WKWebView) {
        let html = Self.renderingHTML(
            for: mermaidCode.htmlEscapedForMermaid,
            isDarkMode: isDarkMode
        )
        webView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastRenderedCode: String?
        var lastRenderedDarkMode: Bool?
        let onImageRendered: ((String) -> Void)?
        let onImageRenderedPNG: ((Data) -> Void)?
        let onHeightChanged: ((CGFloat) -> Void)?
        let onError: ((String) -> Void)?

        init(
            onImageRendered: ((String) -> Void)?,
            onImageRenderedPNG: ((Data) -> Void)?,
            onHeightChanged: ((CGFloat) -> Void)?,
            onError: ((String) -> Void)?
        ) {
            self.onImageRendered = onImageRendered
            self.onImageRenderedPNG = onImageRenderedPNG
            self.onHeightChanged = onHeightChanged
            self.onError = onError
        }
    }
}
