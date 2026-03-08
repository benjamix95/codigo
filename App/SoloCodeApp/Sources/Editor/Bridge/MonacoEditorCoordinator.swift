import AppKit
import Foundation
import WebKit

final class MonacoEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let parent: MonacoEditorView

    weak var webView: WKWebView?
    var isReady = false
    var currentPane: EditorPaneID = .primary
    var currentPath: String?
    var currentContent = ""
    var pendingPath: String?
    var pendingContent = ""
    var lastAppliedOptions = MonacoEditorOptions()
    var lastHandledCommandID: UUID?
    var lastHandledNavigationID: UUID?

    init(parent: MonacoEditorView) {
        self.parent = parent
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            message.name == MonacoEditorView.scriptMessageHandlerName,
            let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]
        switch type {
        case "ready":
            isReady = true
            applySettings()
            applyPendingContent()

        case "contentChanged":
            guard
                let b64 = payload["content"] as? String,
                let path = payload["path"] as? String,
                let decoded = MonacoBridgePayloadCodec.decodeBase64(b64)
            else { return }
            currentContent = decoded
            Task { @MainActor in
                self.parent.handlers.onContentChange(decoded, path)
            }

        case "save":
            guard let path = payload["path"] as? String else { return }
            Task { @MainActor in
                self.parent.handlers.onSaveRequested(path)
            }

        case "fixInChat":
            guard
                let path = payload["path"] as? String,
                let selection = payload["selection"] as? String,
                let line = payload["line"] as? Int
            else { return }
            Task { @MainActor in
                self.parent.handlers.onFixInChat?(path, selection, line)
            }

        case "addToChat":
            guard
                let path = payload["path"] as? String,
                let selection = payload["selection"] as? String,
                let line = payload["line"] as? Int
            else { return }
            Task { @MainActor in
                self.parent.handlers.onAddToChat?(path, selection, line)
            }

        case "cursorChanged":
            guard
                let pane = payload["pane"] as? String,
                let line = payload["line"] as? Int,
                let column = payload["column"] as? Int
            else { return }
            parent.handlers.onCursorChange?(
                EditorCursorPosition(
                    pane: EditorPaneID(rawValue: pane) ?? .primary,
                    line: line,
                    column: column
                )
            )

        case "selectionChanged":
            guard
                let pane = payload["pane"] as? String,
                let startLine = payload["startLine"] as? Int,
                let startColumn = payload["startColumn"] as? Int,
                let endLine = payload["endLine"] as? Int,
                let endColumn = payload["endColumn"] as? Int
            else { return }
            parent.handlers.onSelectionChange?(
                EditorSelectionRange(
                    pane: EditorPaneID(rawValue: pane) ?? .primary,
                    startLine: startLine,
                    startColumn: startColumn,
                    endLine: endLine,
                    endColumn: endColumn
                )
            )

        case "markersChanged":
            guard let markerPayload = MonacoBridgePayloadCodec.decode(MonacoMarkerPayload.self, from: payload) else {
                return
            }
            parent.handlers.onMarkersChanged?(markerPayload)

        case "actionInvoked":
            guard let actionPayload = MonacoBridgePayloadCodec.decode(MonacoActionPayload.self, from: payload) else {
                return
            }
            parent.handlers.onActionInvoked?(actionPayload)

        case "bridgeRequest":
            guard
                let requestType = payload["requestType"] as? String,
                let requestPayload = payload["request"] as? [String: Any],
                let request = MonacoBridgePayloadCodec.decode(MonacoRequestContext.self, from: requestPayload)
            else { return }
            handleBridgeRequest(type: requestType, request: request)

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    func setEditorContent(_ content: String, path: String?) {
        pendingPath = path
        pendingContent = content
        guard isReady, let webView else { return }
        currentPath = path
        currentContent = content
        let script = """
        window.monacoAPI?.setValue(\(MonacoBridgePayloadCodec.jsQuoted(MonacoBridgePayloadCodec.encodeBase64(content))), \(MonacoBridgePayloadCodec.jsQuoted(path ?? "")))
        """
        webView.evaluateJavaScript(script)
    }

    func applyPaneIfNeeded(_ pane: EditorPaneID) {
        guard isReady, currentPane != pane, let webView else { return }
        currentPane = pane
        webView.evaluateJavaScript("window.monacoAPI?.setPane(\(MonacoBridgePayloadCodec.jsQuoted(pane.rawValue)))")
    }

    func applyOptionsIfNeeded(_ options: MonacoEditorOptions) {
        guard isReady, options != lastAppliedOptions, let webView else { return }
        lastAppliedOptions = options
        webView.evaluateJavaScript("window.monacoAPI?.setReadOnly(\(options.readOnly ? "true" : "false"))")
        webView.evaluateJavaScript("window.monacoAPI?.setWordWrap(\(options.wordWrap ? "true" : "false"))")
        webView.evaluateJavaScript("window.monacoAPI?.setMinimap(\(options.minimapEnabled ? "true" : "false"))")
    }

    func reveal(line: Int) {
        guard isReady, let webView else { return }
        webView.evaluateJavaScript("window.monacoAPI?.revealLine(\(line))")
    }

    func runCommand(_ request: EditorMonacoCommandRequest?) {
        guard
            let request,
            request.pane == parent.pane,
            lastHandledCommandID != request.id,
            isReady,
            let webView
        else { return }
        lastHandledCommandID = request.id
        webView.evaluateJavaScript(
            "window.monacoAPI?.runCommand(\(MonacoBridgePayloadCodec.jsQuoted(request.commandId)))"
        )
    }

    func applyDiagnostics(_ diagnostics: [EditorDiagnostic], for path: String?) {
        guard isReady, let path, let webView else { return }
        let markers = diagnostics.map { diagnostic in
            MonacoMarkerPayload.Marker(
                message: diagnostic.message,
                severity: severityValue(for: diagnostic.severity),
                source: diagnostic.source,
                startLineNumber: diagnostic.line,
                startColumn: diagnostic.column,
                endLineNumber: diagnostic.endLine,
                endColumn: diagnostic.endColumn
            )
        }
        guard
            let data = try? MonacoBridgePayloadCodec.encoder.encode(MonacoMarkerPayload(path: path, markers: markers)),
            let json = String(data: data, encoding: .utf8)
        else { return }
        let encoded = MonacoBridgePayloadCodec.encodeBase64(json)
        let script = "window.monacoAPI?.applyDiagnostics(\(MonacoBridgePayloadCodec.jsQuoted(encoded)), \(MonacoBridgePayloadCodec.jsQuoted(path)))"
        webView.evaluateJavaScript(script)
    }

    func navigate(_ request: EditorNavigationRequest?) {
        guard
            let request,
            request.pane == parent.pane,
            request.path == parent.filePath,
            lastHandledNavigationID != request.id
        else { return }
        lastHandledNavigationID = request.id
        reveal(line: request.line)
    }

    private func applyPendingContent() {
        currentPane = parent.pane
        webView?.evaluateJavaScript("window.monacoAPI?.setPane(\(MonacoBridgePayloadCodec.jsQuoted(parent.pane.rawValue)))")
        let path = pendingPath ?? parent.filePath
        let content = pendingContent.isEmpty ? parent.content : pendingContent
        setEditorContent(content, path: path)
        applyOptionsIfNeeded(parent.options)
    }

    private func handleBridgeRequest(type: String, request: MonacoRequestContext) {
        Task {
            let script: String?
            switch EditorBridgeRequestKind(rawValue: type) {
            case .hoverRequested:
                guard let provider = parent.handlers.hoverProvider else { return }
                let payload = await provider(request)
                script = MonacoBridgePayloadCodec.responseScript(requestId: request.requestId, payload: payload)

            case .definitionRequested:
                guard let provider = parent.handlers.definitionProvider else { return }
                let payload = await provider(request)
                script = MonacoBridgePayloadCodec.responseScript(requestId: request.requestId, payload: payload)

            case .referencesRequested:
                guard let provider = parent.handlers.referencesProvider else { return }
                let payload = await provider(request)
                script = MonacoBridgePayloadCodec.responseScript(requestId: request.requestId, payload: payload)

            case .renameRequested:
                guard let provider = parent.handlers.renameProvider else { return }
                let payload = await provider(request)
                script = MonacoBridgePayloadCodec.responseScript(requestId: request.requestId, payload: payload)

            case .outlineRequested:
                guard let provider = parent.handlers.outlineProvider else { return }
                let payload = await provider(request)
                script = MonacoBridgePayloadCodec.responseScript(requestId: request.requestId, payload: payload)

            case .formatRequested, .none:
                return
            }

            guard let script else { return }
            await MainActor.run {
                self.webView?.evaluateJavaScript(script)
            }
        }
    }

    private func applySettings() {
        guard let webView else { return }
        let size = FontPreferences.sanitizeSize(parent.fontSize, kind: .code)
        webView.evaluateJavaScript("window.monacoAPI?.setFontSize(\(size))")
        let family = "'\(parent.fontFamily.replacingOccurrences(of: "'", with: "\\'"))', 'SF Mono', Menlo, monospace"
        webView.evaluateJavaScript("window.monacoAPI?.setFontFamily(\(MonacoBridgePayloadCodec.jsQuoted(family)))")
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? "codigo-dark" : "codigo-light"
        webView.evaluateJavaScript("window.monacoAPI?.setTheme(\(MonacoBridgePayloadCodec.jsQuoted(theme)))")
    }

    private func severityValue(for severity: EditorDiagnosticSeverity) -> Int {
        switch severity {
        case .error: return 8
        case .warning: return 4
        case .info: return 2
        case .hint: return 1
        }
    }
}
