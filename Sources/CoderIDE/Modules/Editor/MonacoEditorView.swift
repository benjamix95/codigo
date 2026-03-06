import SwiftUI
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    static let scriptMessageHandlerName = "monacobridge"

    let pane: EditorPaneID
    let filePath: String?
    let content: String
    let diagnostics: [EditorDiagnostic]
    let commandRequest: EditorMonacoCommandRequest?
    let navigationRequest: EditorNavigationRequest?
    let options: MonacoEditorOptions
    let handlers: MonacoEditorBridgeHandlers

    @AppStorage("ui_code_font_family") var fontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var fontSize = FontPreferences.defaultCodeSize

    func makeCoordinator() -> MonacoEditorCoordinator {
        MonacoEditorCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Self.scriptMessageHandlerName)
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "javaScriptEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear

        context.coordinator.webView = webView
        loadEditor(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.isReady else {
            coordinator.pendingPath = filePath
            coordinator.pendingContent = content
            return
        }
        coordinator.applyPaneIfNeeded(pane)
        if filePath != coordinator.currentPath || content != coordinator.currentContent {
            coordinator.setEditorContent(content, path: filePath)
        }
        coordinator.applyOptionsIfNeeded(options)
        coordinator.applyDiagnostics(diagnostics, for: filePath)
        coordinator.runCommand(commandRequest)
        coordinator.navigate(navigationRequest)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: MonacoEditorCoordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: scriptMessageHandlerName)
    }

    private func loadEditor(_ webView: WKWebView) {
        guard
            let url = MonacoRuntimeAssetResolver.editorHTMLURL(),
            let readAccess = MonacoRuntimeAssetResolver.readAccessURL()
        else {
            let fallback = "<html><body style='color:#888;font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh'><p>Monaco editor resource not found</p></body></html>"
            webView.loadHTMLString(fallback, baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: readAccess)
    }
}
