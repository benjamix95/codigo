import Foundation

extension EventNormalizer {
    static func parseSinglePlanStepUpsert(payload: [String: String]) -> PlanStepUpsertPayload? {
        guard let stepId = (payload["step_id"] ?? payload["stepId"])?.trimmingCharacters(in: .whitespacesAndNewlines), !stepId.isEmpty,
              let status = normalizePlanStepStatus(payload["status"]) else {
            return nil
        }
        return PlanStepUpsertPayload(
            stepId: stepId,
            status: status,
            title: payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: payload["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            targetFile: (payload["target_file"] ?? payload["targetFile"])?.trimmingCharacters(in: .whitespacesAndNewlines),
            linkedFiles: parseStringArray(raw: payload["linked_files"] ?? payload["linkedFiles"]),
            dependsOn: parseStringArray(raw: payload["depends_on"] ?? payload["dependsOn"]),
            notes: payload["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: (payload["conversation_id"] ?? payload["conversationId"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parsePlanStepUpserts(from raw: String?) -> [PlanStepUpsertPayload] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return objects.enumerated().compactMap { index, item in
            let stepId = (
                scalarString(from: item["step_id"])
                    ?? scalarString(from: item["stepId"])
                    ?? scalarString(from: item["id"])
                    ?? String(index + 1)
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stepId.isEmpty else { return nil }
            let status = normalizePlanStepStatus(scalarString(from: item["status"])) ?? .pending
            return PlanStepUpsertPayload(
                stepId: stepId,
                status: status,
                title: (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                description: (item["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                targetFile: ((item["target_file"] as? String) ?? (item["targetFile"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                linkedFiles: parseStringArray(rawValue: item["linked_files"] ?? item["linkedFiles"]),
                dependsOn: parseStringArray(rawValue: item["depends_on"] ?? item["dependsOn"]),
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
        return objects.compactMap { item in
            let stepId = (scalarString(from: item["step_id"]) ?? scalarString(from: item["stepId"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !stepId.isEmpty,
                  let status = normalizePlanStepStatus(scalarString(from: item["status"])) else { return nil }
            return PlanStepBatchUpdateItemPayload(
                stepId: stepId,
                status: status,
                title: (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                description: (item["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                targetFile: ((item["target_file"] as? String) ?? (item["targetFile"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                linkedFiles: parseStringArray(rawValue: item["linked_files"] ?? item["linkedFiles"]),
                dependsOn: parseStringArray(rawValue: item["depends_on"] ?? item["dependsOn"]),
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
            return normalizeStringArray(array)
        }
        if let array = rawValue as? [Any] {
            return normalizeAnyArray(array)
        }
        if let raw = rawValue as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            if trimmed.hasPrefix("["),
               let data = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                if let stringArray = parsed as? [String] {
                    return normalizeStringArray(stringArray)
                }
                if let anyArray = parsed as? [Any] {
                    return normalizeAnyArray(anyArray)
                }
            }
            return normalizeStringArray(trimmed.split(separator: ",").map(String.init))
        }
        if let bool = rawValue as? Bool {
            return [bool ? "true" : "false"]
        }
        if let number = rawValue as? NSNumber {
            if isBooleanNSNumber(number) {
                return [number.boolValue ? "true" : "false"]
            }
            return [number.stringValue]
        }
        return []
    }

    private static func normalizeStringArray(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func normalizeAnyArray(_ values: [Any]) -> [String] {
        var normalized: [String] = []
        for value in values {
            if let string = value as? String {
                normalized.append(string)
                continue
            }
            if let number = value as? NSNumber {
                if isBooleanNSNumber(number) {
                    normalized.append(number.boolValue ? "true" : "false")
                } else {
                    normalized.append(number.stringValue)
                }
            }
        }
        return normalizeStringArray(normalized)
    }

    private static func scalarString(from value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            if isBooleanNSNumber(number) {
                return number.boolValue ? "true" : "false"
            }
            let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func isBooleanNSNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
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
