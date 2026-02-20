import SwiftUI

private enum PlanTraceFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct PlanTraceItem: Identifiable {
    enum Status {
        case running
        case completed
        case failed

        var label: String {
            switch self {
            case .running: return "running"
            case .completed: return "completed"
            case .failed: return "failed"
            }
        }

        var color: Color {
            switch self {
            case .running: return DesignSystem.Colors.warning
            case .completed: return DesignSystem.Colors.success
            case .failed: return DesignSystem.Colors.error
            }
        }
    }

    let id: UUID
    let icon: String
    let iconColor: Color
    let displayTitle: String
    let displaySummary: String
    let rawOutput: String?
    let timestamp: Date
    let status: Status
    let isExpandable: Bool

    init(activity: TaskActivity) {
        id = activity.id
        icon = PlanTraceItem.icon(for: activity.type)
        iconColor = PlanTraceItem.color(for: activity.type)
        displayTitle = PlanTraceItem.title(for: activity)
        displaySummary = PlanTraceItem.summary(for: activity)
        rawOutput = PlanTraceItem.rawOutput(for: activity)
        timestamp = activity.timestamp
        status = PlanTraceItem.status(for: activity)
        isExpandable = !(rawOutput?.isEmpty ?? true)
    }

    private static func title(for activity: TaskActivity) -> String {
        switch activity.type {
        case "command_execution", "bash": return "Eseguo comando"
        case "read_batch_started", "read_batch_completed": return "Leggo file in batch"
        case "mcp_tool_call": return "Invoco tool MCP"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "Ricerca web"
        case "process_paused": return "Processo in pausa"
        case "process_resumed": return "Processo ripreso"
        case "plan_step_update": return "Step piano aggiornato"
        case "file_change", "edit": return "Aggiorno file"
        default: return activity.title
        }
    }

    private static func summary(for activity: TaskActivity) -> String {
        if let command = activity.payload["command"], !command.isEmpty {
            return command
        }
        if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
            return path
        }
        if let query = activity.payload["query"], !query.isEmpty {
            return query
        }
        if let detail = activity.detail, !detail.isEmpty {
            return detail
        }
        return activity.title
    }

    private static func rawOutput(for activity: TaskActivity) -> String? {
        var lines: [String] = []
        if let command = activity.payload["command"], !command.isEmpty {
            lines.append("$ \(command)")
        }
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append("")
            lines.append(output)
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("")
            lines.append("stderr:")
            lines.append(stderr)
        }
        if lines.isEmpty, let detail = activity.detail, !detail.isEmpty {
            lines.append(detail)
        }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func status(for activity: TaskActivity) -> Status {
        switch activity.type {
        case "web_search_failed":
            return .failed
        case "read_batch_completed", "web_search_completed", "process_resumed":
            return .completed
        default:
            return activity.isRunning ? .running : .completed
        }
    }

    private static func icon(for type: String) -> String {
        switch type {
        case "command_execution", "bash": return "terminal.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "plan_step_update": return "list.bullet.rectangle"
        case "file_change", "edit": return "doc.text.fill"
        default: return "circle.fill"
        }
    }

    private static func color(for type: String) -> Color {
        switch type {
        case "command_execution", "bash": return DesignSystem.Colors.warning
        case "read_batch_started", "read_batch_completed": return DesignSystem.Colors.agentColor
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return DesignSystem.Colors.info
        case "process_paused": return DesignSystem.Colors.warning
        case "process_resumed": return DesignSystem.Colors.success
        case "plan_step_update": return DesignSystem.Colors.planColor
        case "file_change", "edit": return DesignSystem.Colors.agentColor
        default: return .secondary
        }
    }
}

struct PlanLiveTraceView: View {
    let activities: [TaskActivity]
    @State private var expandedRawById: Set<UUID> = []

    private var traceItems: [PlanTraceItem] {
        activities.map(PlanTraceItem.init(activity:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan Live Trace")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(traceItems.count) eventi")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            ForEach(traceItems) { item in
                traceRow(item)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.6)
        )
    }

    private func traceRow(_ item: PlanTraceItem) -> some View {
        let isExpanded = expandedRawById.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.iconColor)
                    .frame(width: 14)
                Text(item.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.status.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(item.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.color.opacity(0.12), in: Capsule())
                Text(timestamp(item.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(item.displaySummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if item.isExpandable {
                Button {
                    if isExpanded {
                        expandedRawById.remove(item.id)
                    } else {
                        expandedRawById.insert(item.id)
                    }
                } label: {
                    Text(isExpanded ? "Nascondi output" : "Mostra output")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.info)
                }
                .buttonStyle(.plain)
            }

            if isExpanded, let raw = item.rawOutput {
                Text(truncated(raw))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func timestamp(_ date: Date) -> String {
        PlanTraceFormatters.hms.string(from: date)
    }

    private func truncated(_ text: String, maxChars: Int = 6000) -> String {
        if text.count <= maxChars { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "\n\n… output troncato (\(text.count - maxChars) caratteri nascosti)"
    }
}
