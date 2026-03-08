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
        ),
              var snapshot = loadMutableSnapshot(conversationId: conversationId, createIfMissing: true) else {
            return planError("Error: unable to resolve target plan snapshot")
        }

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

    static func handlePlanSetWalkthrough(args: [String: String]) -> CallTool.Result {
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
}
