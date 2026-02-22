import AppKit
import CoderEngine
import SwiftUI

// MARK: - Assistant Text Chunk

struct AssistantTextChunkView: View {
    let text: String
    let modeColor: Color
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(modeColor.opacity(0.7))
                .frame(width: 24, alignment: .center)
            MarkdownContentView(
                content: text,
                context: context,
                onFileClicked: onFileClicked,
                textAlignment: .leading,
                isStreaming: isStreaming
            )
            .frame(maxWidth: 620, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Timeline Formatters

private enum TimelineFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

struct StepByStepRowView: View {
    let activity: TaskActivity
    let modeColor: Color

    private var statusText: String {
        let raw = (activity.payload["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !raw.isEmpty {
            switch raw {
            case "started", "in_progress", "running":
                return "running"
            case "completed", "done", "success":
                return "completed"
            case "failed", "error":
                return "failed"
            default:
                return raw
            }
        }
        return activity.isRunning ? "running" : "completed"
    }

    private var statusColor: Color {
        switch statusText {
        case "running": return .secondary
        case "completed": return Color(nsColor: .tertiaryLabelColor)
        case "failed": return DesignSystem.Colors.error
        default: return .secondary
        }
    }

    private var iconName: String {
        switch activity.type {
        case "turn_started": return "play.circle.fill"
        case "turn_completed": return "checkmark.circle.fill"
        case "command_execution", "bash": return "terminal.fill"
        case "file_change", "edit": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed":
            return "magnifyingglass"
        case "read_batch_started", "read_batch_completed":
            return "doc.on.doc"
        case "todo_write", "todo_read":
            return "checklist"
        case "process_paused":
            return "pause.circle.fill"
        case "process_resumed":
            return "play.circle.fill"
        default:
            return "gearshape.fill"
        }
    }

    private var detailText: String? {
        let candidates = [
            activity.detail,
            activity.payload["detail"],
            activity.payload["command"],
            activity.payload["path"],
            activity.payload["query"],
            activity.payload["output"],
            activity.payload["tool"],
            activity.payload["title"],
        ]
        for value in candidates {
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != activity.title {
                return String(text.prefix(220))
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, alignment: .center)
                Text(TimelineFormatters.hms.string(from: activity.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            if let detail = detailText {
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: 15)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Todo Timeline Card (wrapper)

struct TodoTimelineCardView: View {
    @ObservedObject var todoStore: TodoStore
    let modeColor: Color
    let onOpenFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("Todo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            TodoLiveInlineCard(store: todoStore, onOpenFile: onOpenFile)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.35), lineWidth: 0.5)
        )
    }
}
