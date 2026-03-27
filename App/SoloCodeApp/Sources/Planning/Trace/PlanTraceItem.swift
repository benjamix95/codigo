import SwiftUI

struct PlanTraceItem: Identifiable {
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
    let activity: TaskActivity
    let icon: String
    let iconColor: Color
    let displayTitle: String
    let displaySummary: String
    let timestamp: Date
    let status: Status
    let isExpandable: Bool
    let fileChange: ToolTraceFileChange?

    init(activity: TaskActivity) {
        let mappedFileChange = ToolTraceFileChangeMapper.from(activity: activity)
        self.activity = activity
        id = activity.id
        icon = PlanTraceItem.icon(for: activity.type)
        iconColor = PlanTraceItem.color(for: activity.type)
        displayTitle = PlanTraceItem.title(for: activity, fileChange: mappedFileChange)
        displaySummary = PlanTraceItem.summary(for: activity)
        timestamp = activity.timestamp
        status = PlanTraceItem.status(for: activity)
        fileChange = mappedFileChange
        isExpandable = mappedFileChange != nil || PlanTraceItem.hasExpandableOutput(activity)
    }

    static func rawOutput(for activity: TaskActivity) -> String? {
        var lines: [String] = []
        if let command = activity.payload["command"], !command.isEmpty {
            lines.append("$ \(UserFacingToolTraceRedaction.redactedIfNeeded(command))")
        }
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let diffPreview = activity.payload["diffPreview"], !diffPreview.isEmpty {
            lines.append("")
            lines.append(diffPreview)
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
            lines.append(UserFacingToolTraceRedaction.redactedIfNeeded(detail))
        }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

private extension PlanTraceItem {
    static func title(for activity: TaskActivity, fileChange: ToolTraceFileChange?) -> String {
        if let fileChange {
            return "\(fileChange.kind.displayTitle) \(fileChange.basename)"
        }
        if let sharedTitle = TaskActivityTextStyle.defaultTitle(for: activity.type) {
            return sharedTitle
        }
        switch activity.type {
        case "command_execution", "bash": return "Running command"
        case "read_batch_started", "read_batch_completed": return "Reading files (batch)"
        case "mcp_tool_call": return userFacingToolName(from: activity.payload)
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "Web search"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "Fetching page"
        case "process_paused": return "Process paused"
        case "process_resumed": return "Process resumed"
        case "semantic_search": return "Semantic search"
        case "read_lints": return "Reading diagnostics"
        default: return activity.title
        }
    }

    static func summary(for activity: TaskActivity) -> String {
        if let command = activity.payload["command"], !command.isEmpty {
            return UserFacingToolTraceRedaction.redactedIfNeeded(command)
        }
        if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
            return path
        }
        if let query = activity.payload["query"], !query.isEmpty {
            return UserFacingToolTraceRedaction.redactedIfNeeded(query)
        }
        if let detail = activity.detail, !detail.isEmpty {
            return UserFacingToolTraceRedaction.redactedIfNeeded(detail)
        }
        return activity.title
    }

    static func hasExpandableOutput(_ activity: TaskActivity) -> Bool {
        if let detail = activity.detail, !detail.isEmpty { return true }
        if let command = activity.payload["command"], !command.isEmpty { return true }
        if let cwd = activity.payload["cwd"], !cwd.isEmpty { return true }
        if let diffPreview = activity.payload["diffPreview"], !diffPreview.isEmpty { return true }
        if let output = activity.payload["output"], !output.isEmpty { return true }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty { return true }
        return false
    }

    static func status(for activity: TaskActivity) -> Status {
        let normalizedStatus = (activity.payload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["failed", "error", "timeout"].contains(normalizedStatus) {
            return .failed
        }
        if ["completed", "done", "success"].contains(normalizedStatus) {
            return .completed
        }

        switch activity.type {
        case "web_search_failed", "web_fetch_failed":
            return .failed
        case "read_batch_completed", "web_search_completed", "web_fetch_completed", "process_resumed",
             "debug_clean", "plan_read", "plan_history_read", "plan_diff",
             "plan_request_user_input":
            return .completed
        default:
            return activity.isRunning ? .running : .completed
        }
    }

    static func icon(for type: String) -> String {
        TaskActivityVisualStyle.icon(for: type)
    }

    static func color(for type: String) -> Color {
        TaskActivityVisualStyle.color(for: type)
    }
}
