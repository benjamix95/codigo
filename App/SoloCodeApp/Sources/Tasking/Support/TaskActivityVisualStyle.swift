import CoderEngine
import SwiftUI

enum TaskActivityVisualStyle {
    static func icon(for rawType: String) -> String {
        switch normalizedType(rawType) {
        case "command_execution", "bash": return "terminal.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "globe"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "todo_write", "todo_read": return "checklist"
        case "plan_step_update": return "list.bullet.rectangle"
        case "plan_create": return "square.and.pencil"
        case "plan_read", "plan_history_read", "plan_diff": return "doc.text.magnifyingglass"
        case "plan_step_upsert", "plan_step_batch_update": return "list.bullet.rectangle.portrait"
        case "plan_step_reorder": return "arrow.up.arrow.down"
        case "plan_step_dependency_set": return "link"
        case "plan_set_walkthrough": return "text.book.closed"
        case "plan_request_user_input": return "questionmark.bubble"
        case "debug_phase_update", "debug_user_request", "debug_resolved": return "ladybug.fill"
        case "debug_context": return "list.clipboard.fill"
        case "debug_log": return "text.badge.plus"
        case "debug_query": return "text.magnifyingglass"
        case "debug_session": return "play.circle.fill"
        case "debug_hypothesize": return "questionmark.diamond.fill"
        case "debug_mark": return "mappin.and.ellipse"
        case "debug_clean": return "trash.fill"
        case "activate_plan_mode": return "list.bullet.rectangle"
        case "activate_debug_mode": return "ladybug.fill"
        case "semantic_search": return "brain"
        case "read_lints": return "exclamationmark.triangle.fill"
        case "file_change", "edit": return "doc.text.fill"
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied": return "exclamationmark.triangle.fill"
        case "agent": return "ant.fill"
        default: return "circle.fill"
        }
    }

    static func color(for rawType: String) -> Color {
        switch normalizedType(rawType) {
        case "plan_step_update": return .secondary
        case "plan_create", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_request_user_input", "activate_plan_mode":
            return DesignSystem.Colors.planColor
        case "plan_read", "plan_history_read", "plan_diff":
            return DesignSystem.Colors.info
        case "debug_phase_update", "debug_user_request", "debug_resolved",
             "debug_hypothesize", "debug_log", "debug_query", "debug_session",
             "debug_mark", "debug_clean", "debug_context", "activate_debug_mode":
            return DesignSystem.Colors.debugColor
        case "semantic_search":
            return DesignSystem.Colors.info
        case "read_lints":
            return DesignSystem.Colors.warning
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied":
            return DesignSystem.Colors.error
        default:
            return .secondary
        }
    }

    private static func normalizedType(_ rawType: String) -> String {
        let lowered = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let canonical = CoderIDECanonicalToolRegistry.shared.runtimeAliasesToCanonicalName[lowered] {
            return canonical
        }
        if lowered.hasPrefix("coderide_"),
           let canonical = CoderIDECanonicalToolRegistry.shared.runtimeName(forMCPName: lowered) {
            return canonical
        }
        return lowered
    }
}
