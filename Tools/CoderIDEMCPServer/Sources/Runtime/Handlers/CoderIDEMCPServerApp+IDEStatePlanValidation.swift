import Foundation
import MCP
import CoderEngine

extension CoderIDEMCPServerApp {
    static func sanitizedStepId(_ raw: String?, fallback: String) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func validatePlanStepId(_ stepId: String, fieldName: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        if stepId.count > 80 {
            return "Error: \(fieldName) must be at most 80 characters"
        }
        if stepId.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Error: \(fieldName) must use only letters, numbers, '.', '_' or '-'"
        }
        return nil
    }

    static func validatePlanStepIdList(_ ids: [String], fieldName: String) -> String? {
        for (index, id) in ids.enumerated() {
            if let error = validatePlanStepId(id, fieldName: "\(fieldName)[\(index)]") {
                return error
            }
        }
        return nil
    }

    static func validateIncomingPlanSteps(_ steps: [[String: Any]]) -> String? {
        for (index, step) in steps.enumerated() {
            guard let explicitId = sanitizedText(step["id"] as? String ?? step["step_id"] as? String) else {
                continue
            }
            if let error = validatePlanStepId(explicitId, fieldName: "steps[\(index)].step_id") {
                return error
            }
        }
        return nil
    }

    static func normalizePlanStep(_ step: [String: Any], fallbackId: String) -> [String: Any] {
        var normalized = step
        let stepId = sanitizedStepId(
            step["id"] as? String ?? step["step_id"] as? String,
            fallback: fallbackId
        )
        normalized["id"] = stepId
        return normalized
    }

    static func deduplicatePlanStepsById(_ steps: [[String: Any]]) -> [[String: Any]] {
        var seenIds = Set<String>()
        var deduped: [[String: Any]] = []
        for (index, rawStep) in steps.enumerated() {
            let normalized = normalizePlanStep(rawStep, fallbackId: String(index + 1))
            let stepId = sanitizedStepId(normalized["id"] as? String, fallback: String(index + 1))
            guard seenIds.insert(stepId).inserted else { continue }
            deduped.append(normalized)
        }
        return deduped
    }

    static func writeMutableSnapshot(_ snapshot: MutablePlanSnapshot) {
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: snapshot.conversationId,
            goal: snapshot.goal,
            chosenPath: snapshot.chosenPath,
            steps: snapshot.steps,
            walkthroughMarkdown: snapshot.walkthroughMarkdown,
            summary: snapshot.summary,
            outcome: snapshot.outcome,
            maxHistoryPerConversation: 50
        )
    }

    static func upsertStep(
        in snapshot: inout MutablePlanSnapshot,
        stepId: String,
        status: String,
        title: String?,
        description: String?,
        targetFile: String?,
        linkedFiles: [String]?,
        dependsOn: [String]?,
        notes: String?
    ) {
        let resolvedTitle = title ?? "Step \(stepId)"
        let resolvedDescription = description ?? resolvedTitle
        if let index = snapshot.steps.firstIndex(where: {
            sanitizedStepId($0["id"] as? String ?? $0["step_id"] as? String, fallback: "") == stepId
        }) {
            snapshot.steps[index]["id"] = stepId
            snapshot.steps[index]["status"] = status
            if let title { snapshot.steps[index]["title"] = title }
            if let description { snapshot.steps[index]["description"] = description }
            if let targetFile { snapshot.steps[index]["target_file"] = targetFile }
            if let linkedFiles { snapshot.steps[index]["linked_files"] = linkedFiles }
            if let dependsOn { snapshot.steps[index]["depends_on"] = dependsOn }
            if let notes { snapshot.steps[index]["notes"] = notes }
        } else {
            snapshot.steps.append([
                "id": stepId,
                "title": resolvedTitle,
                "description": resolvedDescription,
                "target_file": targetFile as Any,
                "status": status,
                "linked_files": linkedFiles ?? [],
                "depends_on": dependsOn ?? [],
                "notes": notes ?? "",
            ])
        }
    }

    static func planError(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: true)
    }

    static func planOK(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: nil)
    }
}
