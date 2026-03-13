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
        ) else {
            return planError("Error: unable to resolve target plan snapshot")
        }
        var rustArgs = normalizedConversationArgs(args)
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["step_id"] = stepId
        rustArgs["status"] = status
        if let title = sanitizedText(args["title"]) {
            rustArgs["title"] = title
        }
        return handlePlanToolWithRust(
            action: "plan_step_update",
            arguments: rustArgs
        )
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

        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["goal"] = goal
        rustArgs["steps"] = encodeJSONAny(incomingSteps) ?? "[]"
        rustArgs["replace_existing"] = replaceExisting ? "true" : "false"
        if let chosenPath {
            rustArgs["chosen_path"] = chosenPath
        }
        return handlePlanToolWithRust(
            action: "plan_create",
            arguments: rustArgs
        )
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
        ) else {
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
        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["step_id"] = stepId
        rustArgs["status"] = status
        if let title = sanitizedText(args["title"]) {
            rustArgs["title"] = title
        }
        if let description = sanitizedText(args["description"]) {
            rustArgs["description"] = description
        }
        if let targetFile = sanitizedText(args["target_file"] ?? args["targetFile"]) {
            rustArgs["target_file"] = targetFile
        }
        if let linkedFiles {
            rustArgs["linked_files"] = encodeJSONString(linkedFiles) ?? "[]"
        }
        if let dependsOn {
            rustArgs["depends_on"] = encodeJSONString(dependsOn) ?? "[]"
        }
        if let notes = sanitizedText(args["notes"]) {
            rustArgs["notes"] = notes
        }
        return handlePlanToolWithRust(
            action: "plan_step_upsert",
            arguments: rustArgs
        )
    }

}

extension CoderIDEMCPServerApp {
    static func handlePlanToolWithRust(
        action: String,
        arguments: [String: String]
    ) -> CallTool.Result {
        let response: PlanStateRustResponse? = ReviewCoreBridge.call(
            functionName: "plan_state_handle_action",
            request: PlanStateRustRequest(
                schemaVersion: 1,
                action: action,
                arguments: arguments
            )
        )

        guard let response else {
            return planError("Error: Rust plan state core unavailable for \(action)")
        }
        if let error = response.error {
            return planError(error.message)
        }
        guard let message = response.message else {
            return planError("Error: Rust plan state core returned no payload for \(action)")
        }
        return CallTool.Result(content: [.text(message)], isError: nil)
    }

    static func encodeJSONString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func encodeJSONAny(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct PlanStateRustRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let arguments: [String: String]
}

private struct PlanStateRustResponse: Decodable {
    let schemaVersion: Int
    let error: PlanStateRustError?
    let message: String?
}

private struct PlanStateRustError: Decodable {
    let code: String
    let message: String
}
