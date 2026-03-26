import SwiftUI

struct TaskActivityRow: View {
    let activity: TaskActivity

    private var typeIcon: String {
        switch activity.type {
        case "edit", "file_change": return "doc.text.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "bash", "command_execution": return "terminal.fill"
        case "search", "web_search", "instant_grep", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "todo_write", "todo_read": return "checklist"
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
        case "activate_plan_mode": return "list.bullet.rectangle"
        case "activate_debug_mode": return "ladybug.fill"
        case "semantic_search": return "brain"
        case "read_lints": return "exclamationmark.triangle.fill"
        case "debug_context": return "list.clipboard.fill"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied": return "exclamationmark.triangle.fill"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "agent": return "ant.fill"
        default: return "circle.fill"
        }
    }

    private var typeColor: Color {
        switch activity.type {
        case "edit", "file_change": return .secondary
        case "read_batch_started", "read_batch_completed": return .secondary
        case "bash", "command_execution": return .secondary
        case "search", "web_search", "instant_grep", "web_search_started", "web_search_completed", "web_search_failed": return .secondary
        case "todo_write", "todo_read": return .secondary
        case "plan_step_update": return .secondary
        case "plan_create", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_request_user_input":
            return DesignSystem.Colors.planColor
        case "plan_read", "plan_history_read", "plan_diff":
            return DesignSystem.Colors.info
        case "debug_phase_update", "debug_user_request", "debug_resolved", "debug_hypothesize": return DesignSystem.Colors.debugColor
        case "debug_log", "debug_query", "debug_session", "debug_mark", "debug_clean":
            return DesignSystem.Colors.debugColor
        case "activate_plan_mode": return DesignSystem.Colors.planColor
        case "activate_debug_mode": return DesignSystem.Colors.debugColor
        case "semantic_search": return DesignSystem.Colors.info
        case "read_lints": return DesignSystem.Colors.warning
        case "debug_context": return DesignSystem.Colors.debugColor
        case "mcp_tool_call": return .secondary
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied": return DesignSystem.Colors.error
        case "process_paused": return .secondary
        case "process_resumed": return .secondary
        case "agent": return .secondary
        default: return .secondary
        }
    }

    private var timeString: String {
        TaskActivityPanelFormatters.timeFormatter.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(typeColor)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .textShimmer(active: activity.isRunning)
                if let detail = activity.userFacingDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textShimmer(active: activity.isRunning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }
}
