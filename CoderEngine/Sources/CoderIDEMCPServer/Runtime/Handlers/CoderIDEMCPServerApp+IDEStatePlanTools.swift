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
        if let error = validatePlanStepId(stepId, fieldName: "'step_id'") {
            return planError(error)
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
        if let error = validateIncomingPlanSteps(parsedIncomingSteps) {
            return planError(error)
        }
        let incomingSteps = deduplicatePlanStepsById(parsedIncomingSteps)

        let parsedReplaceExisting = parseBool(args["replace_existing"] ?? args["replaceExisting"], defaultValue: true)
        if parsedReplaceExisting.isInvalid {
            return planError("Error: 'replace_existing' must be true/false")
        }
        let replaceExisting = parsedReplaceExisting.value
        let chosenPath = sanitizedText(args["chosen_path"] ?? args["chosenPath"])

        var steps = incomingSteps
        var addedStepCount = incomingSteps.count
        var mergedWithExisting = false
        if !replaceExisting,
           let existing = loadMutableSnapshot(conversationId: conversationId, createIfMissing: false) {
            mergedWithExisting = true
            let existingIds = Set(existing.steps.compactMap {
                ($0["id"] as? String ?? $0["step_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            let filteredIncoming = incomingSteps.filter {
                let id = ($0["id"] as? String ?? $0["step_id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !id.isEmpty && !existingIds.contains(id)
            }
            addedStepCount = filteredIncoming.count
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
        if replaceExisting || !mergedWithExisting {
            return planOK("OK — plan snapshot created")
        }
        return planOK("OK — plan snapshot updated (\(addedStepCount) new step(s) merged)")
    }

    private static func handlePlanStepUpsert(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"] ?? args["stepId"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        if let error = validatePlanStepId(stepId, fieldName: "'step_id'") {
            return planError(error)
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
        if let dependsOn, let error = validatePlanStepIdList(dependsOn, fieldName: "'depends_on'") {
            return planError(error)
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

}
