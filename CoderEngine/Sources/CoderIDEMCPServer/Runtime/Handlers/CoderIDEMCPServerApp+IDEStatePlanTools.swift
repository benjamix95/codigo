import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanIDEStateTool(name: String, args: [String: String]) -> CallTool.Result? {
        switch name {
        case "plan_step_update":
            return handleLegacyPlanStepUpdate(args: args)
        case "plan_create":
            return handlePlanCreate(args: args)
        case "plan_read":
            return handlePlanRead(args: args)
        case "plan_step_upsert":
            return handlePlanStepUpsert(args: args)
        case "plan_step_batch_update":
            return handlePlanStepBatchUpdate(args: args)
        case "plan_step_reorder":
            return handlePlanStepReorder(args: args)
        case "plan_step_dependency_set":
            return handlePlanStepDependencySet(args: args)
        case "plan_set_walkthrough":
            return handlePlanSetWalkthrough(args: args)
        case "plan_history_read":
            return handlePlanHistoryRead(args: args)
        case "plan_diff":
            return handlePlanDiff(args: args)
        case "plan_request_user_input":
            return handlePlanRequestUserInput(args: args)
        default:
            return nil
        }
    }

    private static func handleLegacyPlanStepUpdate(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let status = parsePlanStepStatus(args["status"]) else {
            return planError("Error: invalid status. Use: pending, running, done, failed")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        upsertStep(
            in: &snapshot,
            stepId: stepId,
            status: status,
            title: sanitizedText(args["title"]),
            description: nil,
            targetFile: nil,
            linkedFiles: nil,
            dependsOn: nil,
            notes: nil
        )
        writeMutableSnapshot(snapshot)
        return planOK("OK — plan step \(stepId) updated to \(status)")
    }

    private static func handlePlanCreate(args: [String: String]) -> CallTool.Result {
        guard let goal = sanitizedText(args["goal"]), !goal.isEmpty else {
            return planError("Error: 'goal' parameter is required")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true) else {
            return planError("Error: invalid conversation id")
        }
        guard let incomingSteps = parseJSONObjectArray(args["steps"]) else {
            return planError("Error: 'steps' must be a valid JSON array")
        }

        let replaceExisting = parseBool(args["replace_existing"], defaultValue: true)
        let chosenPath = sanitizedText(args["chosen_path"])

        var steps = incomingSteps
        if !replaceExisting,
           let existing = loadMutableSnapshot(conversationId: conversationId, createIfMissing: false) {
            let existingIds = Set(existing.steps.compactMap {
                ($0["id"] as? String ?? $0["step_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            let filteredIncoming = incomingSteps.filter {
                let id = ($0["id"] as? String ?? $0["step_id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !id.isEmpty && !existingIds.contains(id)
            }
            steps = existing.steps + filteredIncoming
        }

        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: goal,
            chosenPath: chosenPath,
            steps: steps,
            walkthroughMarkdown: nil,
            summary: nil,
            outcome: nil,
            maxHistoryPerConversation: 50
        )
        return planOK("OK — plan snapshot created")
    }

    private static func handlePlanRead(args: [String: String]) -> CallTool.Result {
        let conversationId = parseConversationId(args["conversation_id"])
        let includeHistory = parseBool(args["include_history"], defaultValue: false)
        let historyLimit = min(50, max(1, parseInt(args["history_limit"], defaultValue: 10)))
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

    private static func handlePlanStepUpsert(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let status = parsePlanStepStatus(args["status"]) else {
            return planError("Error: invalid status. Use: pending, running, done, failed")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        upsertStep(
            in: &snapshot,
            stepId: stepId,
            status: status,
            title: sanitizedText(args["title"]),
            description: sanitizedText(args["description"]),
            targetFile: sanitizedText(args["target_file"]),
            linkedFiles: parseJSONStringArray(args["linked_files"]),
            dependsOn: parseJSONStringArray(args["depends_on"]),
            notes: sanitizedText(args["notes"])
        )
        writeMutableSnapshot(snapshot)
        return planOK("OK — plan step \(stepId) upserted")
    }

    private static func handlePlanStepBatchUpdate(args: [String: String]) -> CallTool.Result {
        guard let updates = parseJSONObjectArray(args["updates"]), !updates.isEmpty else {
            return planError("Error: 'updates' must be a non-empty JSON array")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        for (index, update) in updates.enumerated() {
            let fallbackId = String(index + 1)
            let stepId = sanitizedStepId(update["step_id"] as? String, fallback: fallbackId)
            guard let status = parsePlanStepStatus(update["status"] as? String) else {
                return planError("Error: updates[\(index)] has invalid status")
            }
            upsertStep(
                in: &snapshot,
                stepId: stepId,
                status: status,
                title: sanitizedText(update["title"] as? String),
                description: sanitizedText(update["description"] as? String),
                targetFile: sanitizedText(update["target_file"] as? String),
                linkedFiles: normalizeStringList(update["linked_files"] ?? update["linkedFiles"]),
                dependsOn: normalizeStringList(update["depends_on"] ?? update["dependsOn"]),
                notes: sanitizedText(update["notes"] as? String)
            )
        }
        writeMutableSnapshot(snapshot)
        return planOK("OK — batch plan update applied (\(updates.count) steps)")
    }

    private static func handlePlanStepReorder(args: [String: String]) -> CallTool.Result {
        guard let orderedStepIds = parseJSONStringArray(args["ordered_step_ids"]), !orderedStepIds.isEmpty else {
            return planError("Error: 'ordered_step_ids' must be a non-empty JSON array")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: false),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: false) else {
            return planError("Error: no plan snapshot found for reorder")
        }

        var byId: [String: [String: Any]] = [:]
        for item in snapshot.steps {
            let id = sanitizedStepId(item["id"] as? String ?? item["step_id"] as? String, fallback: "")
            if !id.isEmpty { byId[id] = item }
        }

        var reordered: [[String: Any]] = []
        var used = Set<String>()
        for stepId in orderedStepIds where !stepId.isEmpty {
            if let existing = byId[stepId] {
                reordered.append(existing)
            } else {
                reordered.append([
                    "id": stepId,
                    "title": "Step \(stepId)",
                    "description": "Step \(stepId)",
                    "status": "pending",
                ])
            }
            used.insert(stepId)
        }
        let remaining = snapshot.steps.filter { step in
            let id = sanitizedStepId(step["id"] as? String ?? step["step_id"] as? String, fallback: "")
            return !id.isEmpty && !used.contains(id)
        }
        snapshot.steps = reordered + remaining
        writeMutableSnapshot(snapshot)
        return planOK("OK — plan step order updated")
    }

    private static func handlePlanStepDependencySet(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let dependsOn = parseJSONStringArray(args["depends_on"]) else {
            return planError("Error: 'depends_on' must be a valid JSON array or comma-separated list")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        let existingStatus = snapshot.steps.first(where: {
            sanitizedStepId($0["id"] as? String ?? $0["step_id"] as? String, fallback: "") == stepId
        }).flatMap { parsePlanStepStatus($0["status"] as? String) } ?? "pending"

        upsertStep(
            in: &snapshot,
            stepId: stepId,
            status: existingStatus,
            title: nil,
            description: nil,
            targetFile: nil,
            linkedFiles: nil,
            dependsOn: dependsOn,
            notes: nil
        )
        writeMutableSnapshot(snapshot)
        return planOK("OK — dependencies set for step \(stepId)")
    }

    private static func handlePlanSetWalkthrough(args: [String: String]) -> CallTool.Result {
        guard let markdown = sanitizedText(args["markdown"]), !markdown.isEmpty else {
            return planError("Error: 'markdown' is required")
        }
        guard let conversationId = resolveConversationId(from: args, createIfMissing: true),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        snapshot.walkthroughMarkdown = markdown
        snapshot.summary = sanitizedText(args["summary"])
        snapshot.outcome = parseOutcome(args["outcome"])
        writeMutableSnapshot(snapshot)
        return planOK("OK — walkthrough stored")
    }

    private static func handlePlanHistoryRead(args: [String: String]) -> CallTool.Result {
        let conversationId = parseConversationId(args["conversation_id"])
        let limit = min(50, max(1, parseInt(args["limit"], defaultValue: 10)))
        let history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: limit)
        guard let json = MCPSharedState.encodedPlanJSONObject(history) else {
            return planError("Error: failed to serialize plan history")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

    private static func handlePlanDiff(args: [String: String]) -> CallTool.Result {
        guard let fromSnapshotId = sanitizedText(args["from_snapshot_id"]), !fromSnapshotId.isEmpty else {
            return planError("Error: 'from_snapshot_id' is required")
        }
        let conversationId = parseConversationId(args["conversation_id"])
        let toSnapshotId = sanitizedText(args["to_snapshot_id"])
        guard let diff = MCPSharedState.readPlanDiffJSONObject(
            conversationId: conversationId,
            fromSnapshotId: fromSnapshotId,
            toSnapshotId: toSnapshotId
        ) else {
            return planError("Error: unable to compute plan diff")
        }
        guard let json = MCPSharedState.encodedPlanJSONObject(diff) else {
            return planError("Error: failed to serialize plan diff")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

}
