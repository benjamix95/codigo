import SwiftUI
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    let filePath: String?
    let content: String
    let onContentChange: (String, String) -> Void
    let onSaveRequested: (String) -> Void
    var onFixInChat: ((String, String, Int) -> Void)?
    var onAddToChat: ((String, String, Int) -> Void)?

    @AppStorage("ui_code_font_family") private var fontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var fontSize = FontPreferences.defaultCodeSize

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "monacobridge")
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
        let coord = context.coordinator
        guard coord.isReady else {
            coord.pendingPath = filePath
            coord.pendingContent = content
            return
        }

        if filePath != coord.currentPath {
            coord.currentPath = filePath
            setEditorContent(webView, content: content, path: filePath)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "monacobridge")
    }

    private func loadEditor(_ webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "monaco-editor", withExtension: "html") else {
            let fallback = "<html><body style='color:#888;font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh'><p>Monaco editor resource not found</p></body></html>"
            webView.loadHTMLString(fallback, baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func setEditorContent(_ webView: WKWebView, content: String, path: String?) {
        let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
        let safePath = (path ?? "").replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.monacoAPI?.setValue('\(b64)', '\(safePath)')") { _, _ in }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: MonacoEditorView
        weak var webView: WKWebView?
        var isReady = false
        var currentPath: String?
        var pendingPath: String?
        var pendingContent: String?

        init(parent: MonacoEditorView) { self.parent = parent }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "monacobridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            let payload = body["payload"] as? [String: Any] ?? [:]

            switch type {
            case "ready":
                isReady = true
                applySettings()
                if let path = pendingPath {
                    currentPath = path
                    let content = pendingContent ?? ""
                    pendingPath = nil
                    pendingContent = nil
                    guard let wv = webView else { return }
                    let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
                    let safePath = path.replacingOccurrences(of: "'", with: "\\'")
                    wv.evaluateJavaScript("window.monacoAPI?.setValue('\(b64)', '\(safePath)')") { _, _ in }
                }

            case "contentChanged":
                guard let b64 = payload["content"] as? String,
                      let path = payload["path"] as? String,
                      let data = Data(base64Encoded: b64),
                      let decoded = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self.parent.onContentChange(decoded, path)
                }

            case "save":
                guard let path = payload["path"] as? String else { return }
                Task { @MainActor in
                    self.parent.onSaveRequested(path)
                }

            case "fixInChat":
                guard let path = payload["path"] as? String,
                      let selection = payload["selection"] as? String,
                      let line = payload["line"] as? Int else { return }
                Task { @MainActor in
                    self.parent.onFixInChat?(path, selection, line)
                }

            case "addToChat":
                guard let path = payload["path"] as? String,
                      let selection = payload["selection"] as? String,
                      let line = payload["line"] as? Int else { return }
                Task { @MainActor in
                    self.parent.onAddToChat?(path, selection, line)
                }

            case "cursorChanged", "selectionChanged":
                break

            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

        private func applySettings() {
            guard let wv = webView else { return }
            let size = FontPreferences.sanitizeSize(parent.fontSize, kind: .code)
            wv.evaluateJavaScript("window.monacoAPI?.setFontSize(\(size))") { _, _ in }

            let family = parent.fontFamily.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("window.monacoAPI?.setFontFamily(\"'\(family)', 'SF Mono', Menlo, monospace\")") { _, _ in }

            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = isDark ? "codigo-dark" : "codigo-light"
            wv.evaluateJavaScript("window.monacoAPI?.setTheme('\(theme)')") { _, _ in }
        }
    }
}
