import Foundation
import MCP
import CoderEngine

extension CoderIDEMCPServerApp {
    struct MutablePlanSnapshot {
        var conversationId: UUID
        var goal: String
        var chosenPath: String?
        var steps: [[String: Any]]
        var walkthroughMarkdown: String?
        var summary: String?
        var outcome: String?
    }

    static func parsePlanStepStatus(_ raw: String?) -> String? {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "pending", "queued", "todo", "open":
            return "pending"
        case "running", "started", "active", "in_progress":
            return "running"
        case "done", "completed", "complete", "finished", "success":
            return "done"
        case "failed", "error", "blocked", "stuck":
            return "failed"
        default:
            return nil
        }
    }

    static func parseOutcome(_ raw: String?) -> String {
        let normalized = (raw ?? "done")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "done", "failed", "cancelled":
            return normalized
        default:
            return "done"
        }
    }

    static func parseJSONStringArray(_ raw: String?) -> [String]? {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let commaSeparated = trimmed.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return commaSeparated.isEmpty ? nil : commaSeparated
    }

    static func parseJSONObjectArray(_ raw: String?) -> [[String: Any]]? {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array
    }

    static func normalizeStringList(_ raw: Any?) -> [String] {
        if let array = raw as? [String] {
            return array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let rawString = raw as? String {
            return parseJSONStringArray(rawString) ?? []
        }
        return []
    }

    static func parseBool(_ raw: String?, defaultValue: Bool) -> Bool {
        let normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return defaultValue }
        return ["1", "true", "yes", "y"].contains(normalized)
    }

    static func parseInt(_ raw: String?, defaultValue: Int) -> Int {
        guard let raw,
              let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultValue
        }
        return value
    }

    static func parseConversationId(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    static func resolveConversationId(
        from args: [String: String],
        createIfMissing: Bool
    ) -> UUID? {
        if let explicit = parseConversationId(args["conversation_id"]) {
            return explicit
        }
        if let latest = latestPlanConversationId() {
            return latest
        }
        return createIfMissing ? UUID() : nil
    }

    static func latestPlanConversationId() -> UUID? {
        guard let latest = MCPSharedState.readLatestPlanSnapshotJSONObject(conversationId: nil),
              let id = latest["conversation_id"] as? String else {
            return nil
        }
        return UUID(uuidString: id)
    }

    static func loadMutableSnapshot(
        conversationId: UUID?,
        createIfMissing: Bool
    ) -> MutablePlanSnapshot? {
        if let conversationId,
           let latest = MCPSharedState.readLatestPlanSnapshotJSONObject(conversationId: conversationId),
           let snapshot = latest["snapshot"] as? [String: Any] {
            return MutablePlanSnapshot(
                conversationId: conversationId,
                goal: (snapshot["goal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "Operational plan in progress",
                chosenPath: (snapshot["chosenPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                steps: (snapshot["steps"] as? [[String: Any]]) ?? [],
                walkthroughMarkdown: snapshot["walkthroughMarkdown"] as? String,
                summary: snapshot["summary"] as? String,
                outcome: snapshot["outcome"] as? String
            )
        }

        guard createIfMissing, let conversationId else { return nil }
        return MutablePlanSnapshot(
            conversationId: conversationId,
            goal: "Operational plan in progress",
            chosenPath: nil,
            steps: [],
            walkthroughMarkdown: nil,
            summary: nil,
            outcome: nil
        )
    }

    static func sanitizedStepId(_ raw: String?, fallback: String) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func sanitizedText(_ raw: String?, fallback: String? = nil) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return trimmed
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
