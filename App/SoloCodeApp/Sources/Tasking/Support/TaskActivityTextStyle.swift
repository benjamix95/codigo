import CoderEngine
import Foundation

enum TaskActivityTextStyle {
    static func defaultTitle(for rawType: String) -> String? {
        switch normalizedType(rawType) {
        case "plan_step_update":
            return "Plan step updated"
        case "plan_create":
            return "Plan created"
        case "plan_read":
            return "Plan read"
        case "plan_step_upsert":
            return "Plan step upsert"
        case "plan_step_batch_update":
            return "Plan steps batch update"
        case "plan_step_reorder":
            return "Plan step order updated"
        case "plan_step_dependency_set":
            return "Plan dependencies updated"
        case "plan_set_walkthrough":
            return "Plan walkthrough updated"
        case "plan_history_read":
            return "Plan history read"
        case "plan_diff":
            return "Plan diff computed"
        case "plan_request_user_input":
            return "Plan clarification requested"
        case "debug_phase_update":
            return "Debug phase update"
        case "debug_user_request":
            return "Debug user request"
        case "debug_resolved":
            return "Debug resolved"
        case "debug_log":
            return "Debug log"
        case "debug_query":
            return "Debug query"
        case "debug_session":
            return "Debug session"
        case "debug_native_session":
            return "Native debug session"
        case "debug_hypothesize":
            return "Debug hypothesis"
        case "debug_mark":
            return "Debug marker"
        case "debug_clean":
            return "Debug clean"
        case "debug_trace_analyze":
            return "Debug trace analysis"
        case "debug_instrument":
            return "Debug instrumentation"
        case "debug_timeline":
            return "Debug timeline"
        case "debug_snapshot":
            return "Debug snapshot"
        case "debug_test_check":
            return "Debug test check"
        case "debug_context":
            return "Debug context"
        default:
            return nil
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
