import Foundation

// MARK: - IDEStateSyntheticEventFactory + Plan Lifecycle

extension IDEStateSyntheticEventFactory {

    static func mapPlanLifecycleEvent(
        tool: String,
        arguments: [String: Any]
    ) -> (type: String, payload: [String: String])? {
        switch tool {
        case "plan_create":
            var payload: [String: String] = [:]
            if let goal = firstNonEmptyString(in: arguments, keys: ["goal"]) { payload["goal"] = goal }
            if let chosenPath = firstNonEmptyString(in: arguments, keys: ["chosen_path", "chosenPath"]) { payload["chosen_path"] = chosenPath }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let steps = jsonStringArgument(in: arguments, keys: ["steps"]) { payload["steps"] = steps }
            return payload.isEmpty ? nil : ("plan_create", payload)

        case "plan_read":
            var payload: [String: String] = [:]
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let includeHistory = firstNonEmptyString(in: arguments, keys: ["include_history", "includeHistory"]) { payload["include_history"] = includeHistory }
            if let historyLimit = firstNonEmptyString(in: arguments, keys: ["history_limit", "historyLimit"]) { payload["history_limit"] = historyLimit }
            return ("plan_read", payload)

        case "plan_step_upsert":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) { payload["status"] = status }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let description = firstNonEmptyString(in: arguments, keys: ["description"]) { payload["description"] = description }
            if let targetFile = firstNonEmptyString(in: arguments, keys: ["target_file", "targetFile"]) { payload["target_file"] = targetFile }
            if let notes = firstNonEmptyString(in: arguments, keys: ["notes"]) { payload["notes"] = notes }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let linkedFiles = jsonStringArgument(in: arguments, keys: ["linked_files", "linkedFiles"]) { payload["linked_files"] = linkedFiles }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            return payload.isEmpty ? nil : ("plan_step_upsert", payload)

        case "plan_step_batch_update":
            var payload: [String: String] = [:]
            if let updates = jsonStringArgument(in: arguments, keys: ["updates"]) { payload["updates"] = updates }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_batch_update", payload)

        case "plan_step_reorder":
            var payload: [String: String] = [:]
            if let ordered = jsonStringArgument(in: arguments, keys: ["ordered_step_ids", "orderedStepIds"]) { payload["ordered_step_ids"] = ordered }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_reorder", payload)

        case "plan_step_dependency_set":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_dependency_set", payload)

        case "plan_set_walkthrough":
            var payload: [String: String] = [:]
            if let markdown = firstNonEmptyString(in: arguments, keys: ["markdown"]) { payload["markdown"] = markdown }
            if let summary = firstNonEmptyString(in: arguments, keys: ["summary"]) { payload["summary"] = summary }
            if let outcome = firstNonEmptyString(in: arguments, keys: ["outcome"]) { payload["outcome"] = outcome }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_set_walkthrough", payload)

        case "plan_history_read":
            var payload: [String: String] = [:]
            if let limit = firstNonEmptyString(in: arguments, keys: ["limit"]) { payload["limit"] = limit }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return ("plan_history_read", payload)

        case "plan_diff":
            var payload: [String: String] = [:]
            if let fromSnapshotID = firstNonEmptyString(in: arguments, keys: ["from_snapshot_id", "fromSnapshotId"]) { payload["from_snapshot_id"] = fromSnapshotID }
            if let toSnapshotID = firstNonEmptyString(in: arguments, keys: ["to_snapshot_id", "toSnapshotId"]) { payload["to_snapshot_id"] = toSnapshotID }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_diff", payload)

        case "plan_request_user_input":
            var payload: [String: String] = [:]
            if let questions = jsonStringArgument(in: arguments, keys: ["questions"]) { payload["questions"] = questions }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let phase = firstNonEmptyString(in: arguments, keys: ["phase"]) { payload["phase"] = phase }
            if let round = firstNonEmptyString(in: arguments, keys: ["round"]) { payload["round"] = round }
            if let context = firstNonEmptyString(in: arguments, keys: ["context"]) { payload["context"] = context }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_request_user_input", payload)

        default:
            return nil
        }
    }
}
