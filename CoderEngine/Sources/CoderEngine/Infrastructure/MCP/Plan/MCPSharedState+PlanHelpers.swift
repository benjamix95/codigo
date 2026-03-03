import Foundation

extension MCPSharedState {
    static func readPlanDocument() -> MCPSharedPlanStateDocument {
        guard let data = try? Data(contentsOf: planStateFilePath),
              let decoded = try? JSONDecoder().decode(MCPSharedPlanStateDocument.self, from: data) else {
            return MCPSharedPlanStateDocument()
        }
        return decoded
    }

    static func writePlanDocument(_ document: MCPSharedPlanStateDocument) {
        ensurePlanDirectory()
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: planStateFilePath, options: .atomic)
    }

    static func resolveConversationId(
        conversationId: UUID?,
        document: MCPSharedPlanStateDocument
    ) -> String? {
        if let conversationId {
            return normalizedConversationId(conversationId)
        }
        if let latest = optionalSanitizedText(document.latestConversationId) {
            return latest
        }
        let keys = document.snapshotsByConversation.keys.sorted()
        return keys.last
    }

    static func resolveSnapshotsForDiff(
        conversationId: UUID?,
        fromSnapshotId: String,
        toSnapshotId: String?,
        document: MCPSharedPlanStateDocument
    ) -> ResolvedPlanDiffSnapshots? {
        let normalizedFromId = optionalSanitizedText(fromSnapshotId)?.lowercased() ?? ""
        guard !normalizedFromId.isEmpty else { return nil }

        let conversationKeys: [String] = {
            if let resolved = resolveConversationId(conversationId: conversationId, document: document) {
                return [resolved]
            }
            return document.snapshotsByConversation.keys.sorted()
        }()

        for key in conversationKeys {
            guard let history = document.snapshotsByConversation[key], !history.isEmpty else { continue }
            guard let from = history.first(where: { $0.snapshotId.lowercased() == normalizedFromId }) else { continue }

            let to: MCPSharedPlanSnapshot? = {
                if let toSnapshotId = optionalSanitizedText(toSnapshotId)?.lowercased() {
                    return history.first(where: { $0.snapshotId.lowercased() == toSnapshotId })
                }
                return history.last
            }()
            guard let to else { continue }
            return ResolvedPlanDiffSnapshots(from: from, to: to)
        }
        return nil
    }

    static func canonicalizedPlanSteps(_ input: [[String: Any]], now: String) -> [MCPSharedPlanStep] {
        var result: [MCPSharedPlanStep] = []
        for (index, raw) in input.enumerated() {
            let fallbackID = String(index + 1)
            let stepId = sanitizedText(raw["id"] as? String ?? raw["step_id"] as? String, fallback: fallbackID)
            let title = sanitizedText(raw["title"] as? String ?? raw["name"] as? String, fallback: "Step \(fallbackID)")
            let description = sanitizedText(raw["description"] as? String, fallback: title)
            let targetFile = optionalSanitizedText(raw["targetFile"] as? String ?? raw["target_file"] as? String)
            let status = normalizePlanStatus(raw["status"] as? String)
            let linkedFiles = normalizeStringArray(raw["linkedFiles"] ?? raw["linked_files"])
            let dependsOn = normalizeStringArray(raw["dependsOn"] ?? raw["depends_on"])
            let notes = optionalSanitizedText(raw["notes"] as? String) ?? ""
            let updatedAt = optionalSanitizedText(raw["updatedAt"] as? String ?? raw["updated_at"] as? String) ?? now
            result.append(MCPSharedPlanStep(
                id: stepId,
                title: title,
                description: description,
                targetFile: targetFile,
                status: status,
                linkedFiles: linkedFiles,
                dependsOn: dependsOn,
                notes: notes,
                updatedAt: updatedAt
            ))
        }
        return result
    }

    static func normalizePlanStatus(_ raw: String?) -> String {
        let normalized = (raw ?? "pending")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "running", "in_progress", "active", "started": return "running"
        case "done", "completed", "complete", "finished", "success": return "done"
        case "failed", "error", "blocked", "stuck": return "failed"
        default: return "pending"
        }
    }

    static func normalizeOutcome(_ raw: String?) -> String {
        let normalized = (raw ?? "done")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "failed", "cancelled", "done": return normalized
        default: return "done"
        }
    }

    static func normalizeStringArray(_ raw: Any?) -> [String] {
        if let array = raw as? [String] {
            return Array(
                Set(array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty })
            ).sorted()
        }
        if let string = raw as? String {
            let parts = string.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            return Array(Set(parts)).sorted()
        }
        return []
    }

    static func signature(for snapshot: MCPSharedPlanSnapshot) -> String {
        let steps = snapshot.steps.map {
            "\($0.id)|\($0.title)|\($0.status)|\($0.description)|\($0.targetFile ?? "")|\($0.linkedFiles.joined(separator: ","))|\($0.dependsOn.joined(separator: ","))|\($0.notes)"
        }.joined(separator: "||")
        return "\(snapshot.goal)|\(snapshot.chosenPath ?? "")|\(steps)|\(snapshot.walkthroughMarkdown ?? "")|\(snapshot.summary ?? "")|\(snapshot.outcome ?? "")"
    }

    static func normalizedConversationId(_ conversationId: UUID) -> String {
        conversationId.uuidString.lowercased()
    }

    static func isoTimestampNow() -> String {
        ISO8601DateFormatter().string(from: .now)
    }

    static func ensurePlanDirectory() {
        let dir = sharedDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func optionalSanitizedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func sanitizedText(_ raw: String?, fallback: String) -> String {
        optionalSanitizedText(raw) ?? fallback
    }

    static func jsonObject<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func jsonArray<T: Encodable>(_ value: [T]) -> [[String: Any]]? {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return object
    }
}
