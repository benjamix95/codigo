import AppKit
import CoderEngine
import SwiftUI

// MARK: - Assistant Text Chunk

struct AssistantTextChunkView: View {
    let text: String
    let modeColor: Color
    let context: ProjectContext?
    let onFileClicked: (String) -> Void

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
                textAlignment: .leading
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

// MARK: - Thinking Card

private enum TimelineFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

struct ThinkingCardView: View {
    let activity: TaskActivity
    let modeColor: Color

    @State private var isExpanded = false
    private var reasoningText: String? {
        let candidates = [
            activity.payload["output"],
            activity.payload["text"],
            activity.payload["reasoning"],
            activity.payload["thinking"],
            activity.payload["content"],
            activity.payload["detail"],
            activity.payload["summary"],
        ]
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { return text }
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(modeColor.opacity(0.7))
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Thinking")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(TimelineFormatters.hms.string(from: activity.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                if let output = reasoningText {
                    Text(output)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? 16 : 4)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(modeColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Tool Execution Card

struct ToolExecutionCardView: View {
    let activity: TaskActivity
    let modeColor: Color

    @State private var isExpanded = false

    private var iconName: String {
        switch activity.type {
        case "bash", "command_execution": return "terminal.fill"
        case "edit", "file_change": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        default: return "gearshape.fill"
        }
    }

    private var iconColor: Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.agentColor
        case .searching: return DesignSystem.Colors.info
        default: return modeColor
        }
    }

    private var isTerminalLike: Bool {
        activity.type == "bash" || activity.type == "command_execution"
    }

    private var cardFill: Color {
        if isTerminalLike {
            // Palette dark slate in stile Codex/ChatGPT terminal cards
            return Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.94)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.6)
    }

    private var cardBorder: Color {
        if isTerminalLike {
            return Color(red: 0.33, green: 0.39, blue: 0.46).opacity(0.82)
        }
        return DesignSystem.Colors.border.opacity(0.6)
    }

    private var commandColor: Color {
        isTerminalLike ? Color(red: 0.81, green: 0.92, blue: 0.79) : .primary
    }

    private var terminalPreview: String? {
        let merged = [
            activity.payload["output"],
            activity.payload["stdout"],
            activity.payload["stderr"],
            activity.payload["detail"],
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        guard let merged else { return nil }
        let lines = merged.split(separator: "\n").prefix(5).map(String.init)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(TimelineFormatters.hms.string(from: activity.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if activity.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if let command = activity.payload["command"], !command.isEmpty {
                    Text("$ \(command)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(commandColor)
                        .lineLimit(isExpanded ? nil : 2)
                        .textSelection(.enabled)
                }
                if !isExpanded, let preview = terminalPreview, isTerminalLike {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                if isExpanded {
                    if let output = activity.payload["output"], !output.isEmpty {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(10)
                            .textSelection(.enabled)
                    }
                    if let path = activity.payload["path"], !path.isEmpty {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignSystem.Colors.success.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Realtime Operations Strip

struct RealtimeOperationsStripView: View {
    let activities: [TaskActivity]

    private var liveItems: [TaskActivity] {
        let filtered = activities.filter { activity in
            if activity.type == "usage" { return false }
            if activity.type == "command_execution" || activity.type == "bash" { return false }
            return true
        }
        var seen = Set<String>()
        let deduped = filtered.reversed().filter { activity in
            let status = (
                activity.payload["status"]
                ?? activity.payload["detail"]
                ?? activity.detail
                ?? ""
            ).lowercased()
            let key = (activity.groupId ?? "")
                + "|"
                + activity.type
                + "|"
                + activity.title
                + "|"
                + status
                + "|"
                + (activity.isRunning ? "running" : "stopped")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        return Array(deduped.prefix(4))
    }

    private func icon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "read_batch_started", "read_batch_completed":
            return "doc.on.doc"
        case "web_search_started", "web_search_completed", "web_search_failed":
            return "magnifyingglass"
        case "mcp_tool_call":
            return "wrench.and.screwdriver.fill"
        case "edit", "file_change":
            return "pencil"
        case "todo_write", "todo_read":
            return "checklist"
        default:
            return activity.phase == .thinking ? "brain" : "gearshape.fill"
        }
    }

    private func accent(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .editing: return DesignSystem.Colors.agentColor
        case .executing: return DesignSystem.Colors.warning
        case .searching: return DesignSystem.Colors.info
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return .secondary
        }
    }

    private func detail(for activity: TaskActivity) -> String? {
        let candidates = [
            activity.detail,
            activity.payload["detail"],
            activity.payload["output"],
            activity.payload["text"],
            activity.payload["reasoning"],
            activity.payload["thinking"],
            activity.payload["summary"],
            activity.payload["path"],
            activity.payload["tool"],
            activity.payload["query"],
        ]
        for value in candidates {
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != activity.title { return text }
        }
        return nil
    }

    var body: some View {
        if !liveItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Operazioni live")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(liveItems) { activity in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: activity))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent(for: activity))
                            .frame(width: 14, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(activity.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if activity.isRunning {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            if let detail = detail(for: activity) {
                                Text(detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 760, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}
