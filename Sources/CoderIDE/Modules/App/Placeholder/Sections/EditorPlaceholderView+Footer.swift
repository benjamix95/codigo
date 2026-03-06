import SwiftUI

extension EditorPlaceholderView {
    var editorFooter: some View {
        HStack(spacing: 12) {
            if let feedback = saveFeedback {
                Text(feedback)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(saveFeedbackIsError ? DesignSystem.Colors.error : .secondary)
            }

            Spacer()

            let summary = editorDiagnosticsStore.summary(for: activeEditorPath)
            if summary.errors > 0 || summary.warnings > 0 {
                Label("\(summary.errors)E \(summary.warnings)W", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(summary.errors > 0 ? DesignSystem.Colors.error : DesignSystem.Colors.warning)
            }

            if let cursor = cursorByPane[editorSplitStore.activePane] {
                Text("Ln \(cursor.line), Col \(cursor.column)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(activeLanguageLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(editorOptions.wordWrap ? "Wrap On" : "Wrap Off") {
                editorOptions.wordWrap.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))

            Button(editorOptions.minimapEnabled ? "Minimap On" : "Minimap Off") {
                editorOptions.minimapEnabled.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.75))
    }

    private var activeLanguageLabel: String {
        guard let path = activeEditorPath else { return "plain" }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "json": return "json"
        case "html", "htm": return "html"
        case "css", "scss": return "css"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "md": return "markdown"
        case "yml", "yaml": return "yaml"
        default: return ext.isEmpty ? "plain" : ext
        }
    }
}
