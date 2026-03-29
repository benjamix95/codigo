import Foundation

extension SwarmLiveReducer {
    static func isErrorEvent(_ activity: TaskActivity) -> Bool {
        let normalizedType = activity.type.lowercased()
        if [
            "web_search_failed", "web_fetch_failed", "tool_execution_error", "tool_validation_error", "tool_timeout",
            "permission_denied", "error",
        ].contains(normalizedType) {
            return true
        }
        let status = (activity.payload["status"] ?? "").lowercased()
        if status == "error" || status == "fatal" {
            return true
        }
        let severity = (activity.payload["severity"] ?? "").lowercased()
        return severity == "error" || severity == "critical"
    }

    static func isWarningEvent(_ activity: TaskActivity) -> Bool {
        guard !isErrorEvent(activity) else { return false }
        let status = (activity.payload["status"] ?? "").lowercased()
        if status == "failed" || status == "warning" {
            return true
        }
        let severity = (activity.payload["severity"] ?? "").lowercased()
        if severity == "warning" {
            return true
        }
        return false
    }

    static func summary(for events: [TaskActivity]) -> String {
        let titles = events.suffix(6).map(\.title).filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "Swarm completed." }
        var seen = Set<String>()
        var compact: [String] = []
        for title in titles where seen.insert(title).inserted {
            compact.append(title)
            if compact.count == 3 { break }
        }
        return "Completed • " + compact.joined(separator: " → ")
    }

    static func transcriptEntry(for activity: TaskActivity) -> SubagentTranscriptEntry? {
        if activity.type == "subagent_text" || activity.type == "reasoning" {
            let source = (activity.payload["source"] ?? "").lowercased()
            if let text = activity.payload["text"] {
                if source == "reasoning" || activity.type == "reasoning"
                    || activity.phase == .thinking {
                    return SubagentTranscriptEntry.reasoning(text, timestamp: activity.timestamp)
                }
                return SubagentTranscriptEntry.assistantText(text, timestamp: activity.timestamp)
            }
        }
        let detail = (activity.detail ?? activity.payload["detail"] ?? "").lowercased()
        let status = (activity.payload["status"] ?? "").lowercased()
        if activity.type == "agent" && (detail == "completed" || status == "completed") {
            let resultText = activity.payload["output"]
                ?? activity.payload["summary"]
                ?? activity.title
            return SubagentTranscriptEntry.result(
                resultText,
                timestamp: activity.timestamp
            )
        }
        return SubagentTranscriptEntry.activity(activity)
    }

    static func bestDetail(
        for activity: TaskActivity,
        displayName: String
    ) -> String? {
        let candidates = [
            activity.detail,
            activity.payload["detail"],
            activity.payload["summary"],
            activity.payload["query"],
            activity.payload["path"],
            activity.payload["command"],
            activity.payload["tool"],
            activity.payload["mcp_tool"],
            activity.payload["name"],
            activity.payload["uri"],
        ]
        for candidate in candidates {
            if let text = SwarmLivePresentation.normalizedSubtitleText(
                candidate,
                excluding: displayName
            ) {
                return text
            }
        }
        return nil
    }

    static func bestDisplayName(for activity: TaskActivity) -> String? {
        let text = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.lowercased() != activity.type.lowercased() else {
            return nil
        }
        let lower = text.lowercased()
        if lower.hasPrefix("sa-") || lower.hasPrefix("swarm-") || lower.hasPrefix("swarm ") { return nil }
        if lower.contains("toolu_") { return nil }
        if lower.hasPrefix("mcp__") || lower.contains("__coderide__") { return nil }
        if lower.hasPrefix("subagent_") { return nil }
        if lower == "started" || lower == "running" || lower == "completed" { return nil }
        return text
    }

    static func dedupeKey(for activity: TaskActivity, owner: String) -> String {
        let bucket = Int(activity.timestamp.timeIntervalSince1970 * 2)
        let status = (activity.payload["status"] ?? "").lowercased()
        let gid = activity.groupId ?? activity.payload["group_id"] ?? SwarmMetadata.canonicalGroupId(from: activity.payload) ?? "-"
        let conversationScope = canonicalConversationScope(from: activity.payload) ?? "-"
        return [
            owner, conversationScope, gid, activity.type, activity.title, status, "\(bucket)",
        ].joined(separator: "|")
    }
}
