import Foundation

@MainActor
final class EditorDiagnosticsStore: ObservableObject {
    @Published private(set) var diagnosticsByPath: [String: [EditorDiagnostic]] = [:]

    private let formattingService = FormattingService()
    private let lintingService = LintingService()

    func diagnostics(for path: String) -> [EditorDiagnostic] {
        diagnosticsByPath[path] ?? []
    }

    func summary(for path: String?) -> EditorDiagnosticSummary {
        guard let path else { return summary(diagnostics: allDiagnostics) }
        return summary(diagnostics: diagnosticsByPath[path] ?? [])
    }

    var allDiagnostics: [EditorDiagnostic] {
        diagnosticsByPath.values.flatMap { $0 }
            .sorted { ($0.filePath, $0.line, $0.column) < ($1.filePath, $1.line, $1.column) }
    }

    func replaceBuiltInDiagnostics(_ payload: MonacoMarkerPayload) {
        let diagnostics = payload.markers.map { marker in
            EditorDiagnostic(
                id: "\(payload.path):\(marker.startLineNumber):\(marker.startColumn):\(marker.message):monaco",
                filePath: payload.path,
                line: marker.startLineNumber,
                column: marker.startColumn,
                endLine: marker.endLineNumber,
                endColumn: marker.endColumn,
                severity: severity(for: marker.severity),
                message: marker.message,
                source: marker.source ?? "monaco"
            )
        }
        replaceDiagnostics(diagnostics, for: payload.path, sources: ["monaco", "typescript", "javascript", "json", "css", "html"])
    }

    func save(
        path: String,
        openFilesStore: OpenFilesStore
    ) async -> (message: String, isError: Bool) {
        var content = openFilesStore.content(for: path)
        let formatConfig = await formattingService.currentConfiguration()
        if formatConfig.formatOnSave {
            let result = await formattingService.format(content: content, filePath: path)
            if result.isSuccess, result.didChange {
                content = result.formattedContent
                openFilesStore.updateContent(content, for: path)
            } else if let error = result.error {
                return (error, true)
            }
        }

        let saved = openFilesStore.save(path: path)
        guard saved else {
            return (openFilesStore.error(for: path) ?? "Errore salvataggio", true)
        }

        let lintConfig = await lintingService.currentConfiguration()
        if lintConfig.lintOnSave {
            let result = await lintingService.lintOnSave(filePath: path)
            applyLintResult(result)
            if let error = result.error, !error.isEmpty {
                return ("Salvato con warning lint: \(error)", false)
            }
            if result.errorCount > 0 || result.warningCount > 0 {
                return ("Salvato • \(result.errorCount) errori, \(result.warningCount) warning", false)
            }
        }

        return ("Salvato", false)
    }

    func formatDocument(
        path: String,
        openFilesStore: OpenFilesStore
    ) async -> (message: String, isError: Bool) {
        let result = await formattingService.format(
            content: openFilesStore.content(for: path),
            filePath: path
        )
        guard result.isSuccess else {
            return (result.error ?? "Formattazione fallita", true)
        }
        openFilesStore.updateContent(result.formattedContent, for: path)
        return result.didChange ? ("Documento formattato", false) : ("Documento già formattato", false)
    }

    private func applyLintResult(_ result: LintResult) {
        let diagnostics = result.diagnostics.map { diagnostic in
            EditorDiagnostic(
                id: diagnostic.id,
                filePath: diagnostic.filePath,
                line: diagnostic.line,
                column: diagnostic.column ?? 1,
                endLine: diagnostic.line,
                endColumn: (diagnostic.column ?? 1) + 1,
                severity: diagnostic.severity == .error ? .error : .warning,
                message: diagnostic.message,
                source: diagnostic.source
            )
        }
        replaceDiagnostics(diagnostics, for: result.filePath, sources: ["swiftlint"])
    }

    private func replaceDiagnostics(_ diagnostics: [EditorDiagnostic], for path: String, sources: [String]) {
        let remaining = (diagnosticsByPath[path] ?? []).filter { !sources.contains($0.source.lowercased()) }
        diagnosticsByPath[path] = (remaining + diagnostics)
            .sorted { ($0.line, $0.column, $0.message) < ($1.line, $1.column, $1.message) }
    }

    private func summary(diagnostics: [EditorDiagnostic]) -> EditorDiagnosticSummary {
        EditorDiagnosticSummary(
            errors: diagnostics.filter { $0.severity == .error }.count,
            warnings: diagnostics.filter { $0.severity == .warning }.count
        )
    }

    private func severity(for value: Int) -> EditorDiagnosticSeverity {
        switch value {
        case 8: return .error
        case 4: return .warning
        case 2: return .info
        default: return .hint
        }
    }
}
