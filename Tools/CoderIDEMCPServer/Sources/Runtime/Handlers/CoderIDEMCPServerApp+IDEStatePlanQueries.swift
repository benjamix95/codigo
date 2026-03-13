import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanRead(args: [String: String]) -> CallTool.Result {
        let parsedIncludeHistory = parseBool(args["include_history"] ?? args["includeHistory"], defaultValue: false)
        if parsedIncludeHistory.isInvalid {
            return planError("Error: 'include_history' must be true/false")
        }
        var rustArgs = normalizedConversationArgs(args)
        rustArgs["include_history"] = parsedIncludeHistory.value ? "true" : "false"
        rustArgs["history_limit"] = String(min(50, max(1, parseInt(args["history_limit"] ?? args["historyLimit"], defaultValue: 10))))
        return handlePlanToolWithRust(action: "plan_read", arguments: rustArgs)
    }

    static func handlePlanHistoryRead(args: [String: String]) -> CallTool.Result {
        var rustArgs = normalizedConversationArgs(args)
        rustArgs["limit"] = String(min(50, max(1, parseInt(args["limit"], defaultValue: 10))))
        return handlePlanToolWithRust(action: "plan_history_read", arguments: rustArgs)
    }

    static func handlePlanDiff(args: [String: String]) -> CallTool.Result {
        guard let fromSnapshotId = sanitizedText(args["from_snapshot_id"] ?? args["fromSnapshotId"]), !fromSnapshotId.isEmpty else {
            return planError("Error: 'from_snapshot_id' is required")
        }
        var rustArgs = normalizedConversationArgs(args)
        rustArgs["from_snapshot_id"] = fromSnapshotId
        if let toSnapshotId = sanitizedText(args["to_snapshot_id"] ?? args["toSnapshotId"]) {
            rustArgs["to_snapshot_id"] = toSnapshotId
        }
        return handlePlanToolWithRust(action: "plan_diff", arguments: rustArgs)
    }
}
