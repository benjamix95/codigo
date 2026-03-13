import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanStepBatchUpdate(args: [String: String]) -> CallTool.Result {
        guard let updates = parseJSONObjectArray(args["updates"]), !updates.isEmpty else {
            return planError("Error: 'updates' must be a non-empty JSON array")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ) else {
            return planError("Error: unable to resolve target plan snapshot")
        }
        var normalizedUpdates: [[String: Any]] = []
        for (index, update) in updates.enumerated() {
            let stepId = sanitizedText((update["step_id"] ?? update["stepId"]) as? String)
            guard let stepId, !stepId.isEmpty else {
                return planError("Error: updates[\(index)] requires non-empty step_id")
            }
            if let error = validatePlanStepId(stepId, fieldName: "updates[\(index)].step_id") {
                return planError(error)
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
            if let error = validatePlanStepIdList(dependsOn.values, fieldName: "updates[\(index)].depends_on") {
                return planError(error)
            }
            normalizedUpdates.append([
                "stepId": stepId,
                "status": status,
                "title": sanitizedText(update["title"] as? String) as Any,
                "description": sanitizedText(update["description"] as? String) as Any,
                "targetFile": sanitizedText((update["target_file"] ?? update["targetFile"]) as? String) as Any,
                "linkedFiles": linkedFiles.values,
                "dependsOn": dependsOn.values,
                "notes": sanitizedText(update["notes"] as? String) as Any,
            ])
        }
        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["updates"] = encodeJSONAny(normalizedUpdates) ?? "[]"
        return handlePlanToolWithRust(
            action: "plan_step_batch_update",
            arguments: rustArgs
        )
    }

    static func handlePlanStepReorder(args: [String: String]) -> CallTool.Result {
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
        if let error = validatePlanStepIdList(orderedStepIds, fieldName: "'ordered_step_ids'") {
            return planError(error)
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: false,
            allowLatestFallback: false
        ) else {
            return planError("Error: no plan snapshot found for reorder")
        }
        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["ordered_step_ids"] = encodeJSONString(orderedStepIds) ?? "[]"
        return handlePlanToolWithRust(
            action: "plan_step_reorder",
            arguments: rustArgs
        )
    }

    static func handlePlanStepDependencySet(args: [String: String]) -> CallTool.Result {
        guard let stepId = sanitizedText(args["step_id"] ?? args["stepId"]), !stepId.isEmpty else {
            return planError("Error: 'step_id' is required")
        }
        if let error = validatePlanStepId(stepId, fieldName: "'step_id'") {
            return planError(error)
        }
        guard let dependsOn = parseJSONStringArray(args["depends_on"] ?? args["dependsOn"]) else {
            return planError("Error: 'depends_on' must be a valid JSON string array")
        }
        if let error = validatePlanStepIdList(dependsOn, fieldName: "'depends_on'") {
            return planError(error)
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ) else {
            return planError("Error: unable to resolve target plan snapshot")
        }
        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["step_id"] = stepId
        rustArgs["depends_on"] = encodeJSONString(dependsOn) ?? "[]"
        return handlePlanToolWithRust(
            action: "plan_step_dependency_set",
            arguments: rustArgs
        )
    }

    static func handlePlanSetWalkthrough(args: [String: String]) -> CallTool.Result {
        guard let markdown = sanitizedText(args["markdown"]), !markdown.isEmpty else {
            return planError("Error: 'markdown' is required")
        }
        let normalizedArgs = normalizedConversationArgs(args)
        guard let conversationId = resolveConversationId(
            from: normalizedArgs,
            createIfMissing: true,
            allowLatestFallback: false
        ) else {
            return planError("Error: unable to resolve target plan snapshot")
        }
        var rustArgs = normalizedArgs
        rustArgs["conversation_id"] = conversationId.uuidString.lowercased()
        rustArgs["markdown"] = markdown
        if let summary = sanitizedText(args["summary"]) {
            rustArgs["summary"] = summary
        }
        rustArgs["outcome"] = parseOutcome(args["outcome"])
        return handlePlanToolWithRust(
            action: "plan_set_walkthrough",
            arguments: rustArgs
        )
    }
}
