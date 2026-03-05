import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanIDEStateTool(name: String, args: [String: String]) -> CallTool.Result? {
        let planToolNames: Set<String> = [
            "plan_step_update",
            "plan_create",
            "plan_read",
            "plan_step_upsert",
            "plan_step_batch_update",
            "plan_step_reorder",
            "plan_step_dependency_set",
            "plan_set_walkthrough",
            "plan_history_read",
            "plan_diff",
            "plan_request_user_input",
        ]
        guard planToolNames.contains(name) else { return nil }

        let conversationIdArg = args["conversation_id"] ?? args["conversationId"]
        if hasInvalidConversationIdArgument(conversationIdArg) {
            return planError("Error: 'conversation_id' must be a valid UUID")
        }
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
        guard let stepId = sanitizedText(args["step_id"] ?? args["stepId"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let status = parsePlanStepStatus(args["status"]) else {
            return planError("Error: invalid status. Use: pending, running, done, failed")
        }
        guard let conversationId = resolveConversationId(
            from: args,
            createIfMissing: true,
            allowLatestFallback: false
        ),
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
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ) else {
            return planError("Error: invalid conversation id")
        }
        guard let parsedIncomingSteps = parseJSONObjectArray(args["steps"]) else {
            return planError("Error: 'steps' must be a valid JSON array")
        }
        let incomingSteps = deduplicatePlanStepsById(parsedIncomingSteps)

        let parsedReplaceExisting = parseBool(args["replace_existing"] ?? args["replaceExisting"], defaultValue: true)
        if parsedReplaceExisting.isInvalid {
            return planError("Error: 'replace_existing' must be true/false")
        }
        let replaceExisting = parsedReplaceExisting.value
        let chosenPath = sanitizedText(args["chosen_path"] ?? args["chosenPath"])

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
            steps = deduplicatePlanStepsById(existing.steps + filteredIncoming)
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

    private static func handlePlanStepUpsert(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"] ?? args["stepId"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let status = parsePlanStepStatus(args["status"]) else {
            return planError("Error: invalid status. Use: pending, running, done, failed")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        let rawLinkedFiles = args["linked_files"] ?? args["linkedFiles"]
        let linkedFiles = parseJSONStringArray(rawLinkedFiles)
        if rawLinkedFiles != nil, linkedFiles == nil {
            return planError("Error: 'linked_files' must be a valid JSON string array")
        }
        let rawDependsOn = args["depends_on"] ?? args["dependsOn"]
        let dependsOn = parseJSONStringArray(rawDependsOn)
        if rawDependsOn != nil, dependsOn == nil {
            return planError("Error: 'depends_on' must be a valid JSON string array")
        }

        upsertStep(
            in: &snapshot,
            stepId: stepId,
            status: status,
            title: sanitizedText(args["title"]),
            description: sanitizedText(args["description"]),
            targetFile: sanitizedText(args["target_file"] ?? args["targetFile"]),
            linkedFiles: linkedFiles,
            dependsOn: dependsOn,
            notes: sanitizedText(args["notes"])
        )
        writeMutableSnapshot(snapshot)
        return planOK("OK — plan step \(stepId) upserted")
    }

    private static func handlePlanStepBatchUpdate(args: [String: String]) -> CallTool.Result {
        guard let updates = parseJSONObjectArray(args["updates"]), !updates.isEmpty else {
            return planError("Error: 'updates' must be a non-empty JSON array")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

        for (index, update) in updates.enumerated() {
            let stepId = sanitizedText((update["step_id"] ?? update["stepId"]) as? String)
            guard let stepId, !stepId.isEmpty else {
                return planError("Error: updates[\(index)] requires non-empty step_id")
            }
            guard let status = parsePlanStepStatus(update["status"] as? String) else {
                return planError("Error: updates[\(index)] has invalid status")
            }
            let linkedFilesField = update["linked_files"] ?? update["linkedFiles"]
            let linkedFiles = parseStringList(linkedFilesField)
            if linkedFiles.isInvalid {
                return planError("Error: updates[\(index)] has invalid linked_files (expected string array)")
            }
            let dependsOnField = update["depends_on"] ?? update["dependsOn"]
            let dependsOn = parseStringList(dependsOnField)
            if dependsOn.isInvalid {
                return planError("Error: updates[\(index)] has invalid depends_on (expected string array)")
            }
            upsertStep(
                in: &snapshot,
                stepId: stepId,
                status: status,
                title: sanitizedText(update["title"] as? String),
                description: sanitizedText(update["description"] as? String),
                targetFile: sanitizedText((update["target_file"] ?? update["targetFile"]) as? String),
                linkedFiles: linkedFiles.values,
                dependsOn: dependsOn.values,
                notes: sanitizedText(update["notes"] as? String)
            )
        }
        writeMutableSnapshot(snapshot)
        return planOK("OK — batch plan update applied (\(updates.count) steps)")
    }

    private static func handlePlanStepReorder(args: [String: String]) -> CallTool.Result {
        guard let orderedStepIdsRaw = parseJSONStringArray(args["ordered_step_ids"] ?? args["orderedStepIds"]), !orderedStepIdsRaw.isEmpty else {
            return planError("Error: 'ordered_step_ids' must be a non-empty JSON array")
        }
        let orderedStepIds = orderedStepIdsRaw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !orderedStepIds.isEmpty else {
            return planError("Error: 'ordered_step_ids' must contain at least one id")
        }
        guard Set(orderedStepIds).count == orderedStepIds.count else {
            return planError("Error: 'ordered_step_ids' must not contain duplicate ids")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: false,
            allowLatestFallback: false
        ),
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
        guard let stepId = sanitizedText(args["step_id"] ?? args["stepId"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        guard let dependsOn = parseJSONStringArray(args["depends_on"] ?? args["dependsOn"]) else {
            return planError("Error: 'depends_on' must be a valid JSON string array")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ),
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
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ),
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
        let conversationId = parseConversationId(args["conversation_id"] ?? args["conversationId"])
        let limit = min(50, max(1, parseInt(args["limit"], defaultValue: 10)))
        let history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: limit)
        guard let json = MCPSharedState.encodedPlanJSONObject(history) else {
            return planError("Error: failed to serialize plan history")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

    private static func handlePlanDiff(args: [String: String]) -> CallTool.Result {
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
            return planError("Error: unable to compute plan diff")
        }
        guard let json = MCPSharedState.encodedPlanJSONObject(diff) else {
            return planError("Error: failed to serialize plan diff")
        }
        return CallTool.Result(content: [.text(json)], isError: nil)
    }

    private static func normalizedConversationArgs(_ args: [String: String]) -> [String: String] {
        var normalized = args
        if normalized["conversation_id"] == nil, let conversationId = normalized["conversationId"] {
            normalized["conversation_id"] = conversationId
        }
        return normalized
    }

}
