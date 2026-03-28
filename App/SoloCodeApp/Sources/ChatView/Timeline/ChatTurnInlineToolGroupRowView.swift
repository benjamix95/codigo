import SwiftUI

struct ChatTurnInlineToolGroupRowView: View {
    let event: ToolTraceEvent
    var messageIsStreaming: Bool = true
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    private var presentation: ChatTurnInlineToolGroupRowPresentation {
        ChatTurnInlineToolGroupRowPresentation.make(event: event)
    }

    private var showsRunningChrome: Bool {
        event.isRunning && messageIsStreaming
    }

    private var openPath: String? {
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return FileChangePreviewResolver.resolveOpenPath(
                for: change,
                workspaceHints: workspaceHints
            )
        }
        let candidate = event.payload["path"] ?? event.payload["file"] ?? ""
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            WorkspaceCatalogToolIcon(event: event)
                .frame(width: 14, alignment: .center)

            Text(presentation.actionLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)

            Group {
                if let openPath {
                    Button {
                        onOpenFile(openPath)
                    } label: {
                        emphasizedText
                    }
                    .buttonStyle(.plain)
                } else {
                    emphasizedText
                }
            }

            if let detailText = presentation.detailText {
                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsRunningChrome {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            } else if MessageToolTraceView.isErrorType(event) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.65), lineWidth: 0.5)
        )
    }

    private var emphasizedText: some View {
        Text(presentation.emphasizedText)
            .font(
                .system(
                    size: 10.5,
                    weight: .semibold,
                    design: presentation.usesMonospacedEmphasis ? .monospaced : .default
                )
            )
            .foregroundStyle(presentation.accentColor.opacity(0.95))
            .lineLimit(1)
            .textShimmer(active: showsRunningChrome)
    }
}

struct ChatTurnInlineToolGroupRowPresentation: Equatable {
    let actionLabel: String
    let emphasizedText: String
    let detailText: String?
    let usesMonospacedEmphasis: Bool
    let accentColor: Color

    static func make(event: ToolTraceEvent) -> Self {
        let tool = MessageToolTraceToolIdentity.normalizedToolName(for: event)
        let target = displayTarget(for: event)

        if event.type == "bash" || event.type == "command_execution" || tool == "bash" {
            return .init(
                actionLabel: "Terminale",
                emphasizedText: target.isEmpty ? event.title : target,
                detailText: nil,
                usesMonospacedEmphasis: true,
                accentColor: DesignSystem.Colors.warning
            )
        }

        switch tool {
        case "read", "read_range", "batch_read":
            return .init(
                actionLabel: "Lettura",
                emphasizedText: fallbackEmphasis(target: target, eventTitle: event.title),
                detailText: nil,
                usesMonospacedEmphasis: false,
                accentColor: DesignSystem.Colors.info
            )
        case "list_dir", "glob", "find_files", "file_outline":
            return .init(
                actionLabel: "Elenco",
                emphasizedText: fallbackEmphasis(target: target, eventTitle: event.title),
                detailText: nil,
                usesMonospacedEmphasis: false,
                accentColor: DesignSystem.Colors.browserColor
            )
        case "grep", "search", "semantic_search", "codebase_search", "find_symbol", "find_references":
            return .init(
                actionLabel: "Ricerca",
                emphasizedText: fallbackEmphasis(target: target, eventTitle: event.title),
                detailText: nil,
                usesMonospacedEmphasis: false,
                accentColor: DesignSystem.Colors.reviewColor
            )
        default:
            return .init(
                actionLabel: event.title,
                emphasizedText: fallbackEmphasis(target: target, eventTitle: event.title),
                detailText: nil,
                usesMonospacedEmphasis: false,
                accentColor: DesignSystem.Colors.planColor
            )
        }
    }

    private static func displayTarget(for event: ToolTraceEvent) -> String {
        let raw = event.payload["path"]
            ?? event.payload["file"]
            ?? event.payload["query"]
            ?? event.payload["command"]
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return change.path ?? change.basename
        }
        if event.type == "bash" || event.type == "command_execution" {
            return String(trimmed.prefix(120))
        }
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    private static func fallbackEmphasis(target: String, eventTitle: String) -> String {
        let cleaned = target.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? eventTitle : cleaned
    }
}
