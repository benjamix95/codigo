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
            lines.append("$ \(command)")
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
            lines.append(detail)
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
        switch activity.type {
        case "command_execution", "bash": return "Running command"
        case "read_batch_started", "read_batch_completed": return "Reading files (batch)"
        case "mcp_tool_call": return userFacingToolName(from: activity.payload)
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "Web search"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "Fetching page"
        case "process_paused": return "Process paused"
        case "process_resumed": return "Process resumed"
        case "plan_step_update": return "Plan step updated"
        case "plan_create": return "Plan created"
        case "plan_read": return "Plan read"
        case "plan_step_upsert": return "Plan step upsert"
        case "plan_step_batch_update": return "Plan steps batch update"
        case "plan_step_reorder": return "Plan step order updated"
        case "plan_step_dependency_set": return "Plan dependencies updated"
        case "plan_set_walkthrough": return "Plan walkthrough updated"
        case "plan_history_read": return "Plan history read"
        case "plan_diff": return "Plan diff computed"
        case "plan_request_user_input": return "Plan clarification requested"
        case "debug_phase_update": return "Debug phase"
        case "debug_user_request": return "Debug user request"
        case "debug_resolved": return "Debug resolved"
        case "debug_log": return "Debug log"
        case "debug_query": return "Debug query"
        case "debug_session": return "Debug session"
        case "debug_hypothesize": return "Debug hypothesis"
        case "debug_mark": return "Debug marker"
        case "debug_clean": return "Debug clean"
        case "semantic_search": return "Semantic search"
        case "read_lints": return "Reading diagnostics"
        case "debug_context": return "Debug context"
        default: return activity.title
        }
    }

    static func summary(for activity: TaskActivity) -> String {
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
        switch type {
        case "command_execution", "bash": return "terminal.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "globe"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "plan_step_update": return "list.bullet.rectangle"
        case "plan_create": return "square.and.pencil"
        case "plan_read", "plan_history_read", "plan_diff": return "doc.text.magnifyingglass"
        case "plan_step_upsert", "plan_step_batch_update": return "list.bullet.rectangle.portrait"
        case "plan_step_reorder": return "arrow.up.arrow.down"
        case "plan_step_dependency_set": return "link"
        case "plan_set_walkthrough": return "text.book.closed"
        case "plan_request_user_input": return "questionmark.bubble"
        case "debug_phase_update", "debug_user_request", "debug_resolved", "debug_hypothesize": return "ladybug.fill"
        case "debug_log": return "text.badge.plus"
        case "debug_query": return "text.magnifyingglass"
        case "debug_session": return "play.circle.fill"
        case "debug_mark": return "mappin.and.ellipse"
        case "debug_clean": return "trash.fill"
        case "semantic_search": return "brain"
        case "read_lints": return "exclamationmark.triangle.fill"
        case "debug_context": return "list.clipboard.fill"
        case "file_change", "edit": return "doc.text.fill"
        default: return "circle.fill"
        }
    }

    static func color(for type: String) -> Color {
        switch type {
        case "command_execution", "bash": return DesignSystem.Colors.warning
        case "read_batch_started", "read_batch_completed": return DesignSystem.Colors.agentColor
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return DesignSystem.Colors.info
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return DesignSystem.Colors.info
        case "process_paused": return DesignSystem.Colors.warning
        case "process_resumed": return DesignSystem.Colors.success
        case "plan_step_update", "plan_create", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_request_user_input":
            return DesignSystem.Colors.planColor
        case "plan_read", "plan_history_read", "plan_diff":
            return DesignSystem.Colors.info
        case "debug_phase_update", "debug_user_request", "debug_resolved", "debug_hypothesize": return DesignSystem.Colors.debugColor
        case "debug_log", "debug_query", "debug_session", "debug_mark", "debug_clean":
            return DesignSystem.Colors.debugColor
        case "semantic_search": return DesignSystem.Colors.info
        case "read_lints": return DesignSystem.Colors.warning
        case "debug_context": return DesignSystem.Colors.debugColor
        case "file_change", "edit": return DesignSystem.Colors.agentColor
        default: return .secondary
        }
    }
}
