import Foundation

extension EventNormalizer {
    static func parseSinglePlanStepUpsert(payload: [String: String]) -> PlanStepUpsertPayload? {
        guard let stepId = payload["step_id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !stepId.isEmpty,
              let status = normalizePlanStepStatus(payload["status"]) else {
            return nil
        }
        return PlanStepUpsertPayload(
            stepId: stepId,
            status: status,
            title: payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: payload["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            targetFile: payload["target_file"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            linkedFiles: parseStringArray(raw: payload["linked_files"]),
            dependsOn: parseStringArray(raw: payload["depends_on"]),
            notes: payload["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: payload["conversation_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parsePlanStepUpserts(from raw: String?) -> [PlanStepUpsertPayload] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return objects.enumerated().compactMap { index, item in
            let stepId = ((item["step_id"] as? String) ?? (item["id"] as? String) ?? String(index + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stepId.isEmpty,
                  let status = normalizePlanStepStatus(item["status"] as? String) else { return nil }
            return PlanStepUpsertPayload(
                stepId: stepId,
                status: status,
                title: (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                description: (item["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                targetFile: (item["target_file"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                linkedFiles: parseStringArray(rawValue: item["linked_files"]),
                dependsOn: parseStringArray(rawValue: item["depends_on"]),
                notes: (item["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                conversationId: nil
            )
        }
    }

    static func parseBatchUpdateItems(from raw: String?) -> [PlanStepBatchUpdateItemPayload] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return objects.enumerated().compactMap { index, item in
            let stepId = ((item["step_id"] as? String) ?? String(index + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stepId.isEmpty,
                  let status = normalizePlanStepStatus(item["status"] as? String) else { return nil }
            return PlanStepBatchUpdateItemPayload(
                stepId: stepId,
                status: status,
                title: (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                description: (item["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                targetFile: (item["target_file"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                linkedFiles: parseStringArray(rawValue: item["linked_files"]),
                dependsOn: parseStringArray(rawValue: item["depends_on"]),
                notes: (item["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func parseStringArray(raw: String?) -> [String] {
        guard let raw else { return [] }
        return parseStringArray(rawValue: raw)
    }

    static func parseStringArray(rawValue: Any?) -> [String] {
        if let array = rawValue as? [String] {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let raw = rawValue as? String,
           let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    static func normalizePlanStepStatus(_ raw: String?) -> PlanStepStatus? {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "pending", "queued", "todo", "open": return .pending
        case "running", "started", "active", "in_progress": return .running
        case "done", "completed", "complete", "finished", "success": return .done
        case "failed", "error", "blocked", "stuck": return .failed
        default: return nil
        }
    }
}
