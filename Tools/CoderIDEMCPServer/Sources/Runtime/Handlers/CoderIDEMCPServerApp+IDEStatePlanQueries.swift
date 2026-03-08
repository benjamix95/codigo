import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanRead(args: [String: String]) -> CallTool.Result {
        let conversationId = parseConversationId(args["conversation_id"] ?? args["conversationId"])
        let parsedIncludeHistory = parseBool(args["include_history"] ?? args["includeHistory"], defaultValue: false)
        if parsedIncludeHistory.isInvalid {
            return planError("Error: 'include_history' must be true/false")
        }
        let includeHistory = parsedIncludeHistory.value
        let historyLimit = min(50, max(1, parseInt(args["history_limit"] ?? args["historyLimit"], defaultValue: 10)))
        guard let object = MCPSharedState.readLatestPlanSnapshotJSONObject(
            conversationId: conversationId,
            includeHistory: includeHistory,
            historyLimit: historyLimit
        ) else {
            return CallTool.Result(content: [.text("No plan snapshots found.")], isError: nil)
        }
        guard let json = MCPSharedState.encodedPlanJSONObject(object) else {
            return planError("Error: failed to serialize plan snapshot")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

    static func handlePlanHistoryRead(args: [String: String]) -> CallTool.Result {
        let conversationId = parseConversationId(args["conversation_id"] ?? args["conversationId"])
        let limit = min(50, max(1, parseInt(args["limit"], defaultValue: 10)))
        let history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: limit)
        guard let json = MCPSharedState.encodedPlanJSONObject(history) else {
            return planError("Error: failed to serialize plan history")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

    static func handlePlanDiff(args: [String: String]) -> CallTool.Result {
        guard let fromSnapshotId = sanitizedText(args["from_snapshot_id"] ?? args["fromSnapshotId"]), !fromSnapshotId.isEmpty else {
            return planError("Error: 'from_snapshot_id' is required")
        }
        let conversationId = parseConversationId(args["conversation_id"] ?? args["conversationId"])
        let toSnapshotId = sanitizedText(args["to_snapshot_id"] ?? args["toSnapshotId"])
        guard let diff = MCPSharedState.readPlanDiffJSONObject(
            conversationId: conversationId,
            fromSnapshotId: fromSnapshotId,
            toSnapshotId: toSnapshotId
        ) else {
            let targetSuffix = toSnapshotId.map { " and to_snapshot_id '\($0)'" } ?? ""
            return planError("Error: unable to compute plan diff for from_snapshot_id '\(fromSnapshotId)'\(targetSuffix)")
        }
        guard let json = MCPSharedState.encodedPlanJSONObject(diff) else {
            return planError("Error: failed to serialize plan diff")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }
}
