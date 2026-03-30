import Foundation

enum SubagentLaunchAcknowledgement {
    static func isLaunchAck(activity: TaskActivity) -> Bool {
        isSubagentTool(payload: activity.payload) && isLaunchAckText(
            activity.payload["output"]
                ?? activity.detail
                ?? activity.payload["detail"]
                ?? activity.title
        )
    }

    static func launchDetail(activity: TaskActivity) -> String {
        let tool = activity.payload["readable_name"]
            ?? activity.payload["agent_name"]
            ?? activity.title
        let trimmedTool = normalizedLaunchSource(tool)
        if trimmedTool.isEmpty {
            return "launch acknowledged"
        }
        return "\(trimmedTool) • launch acknowledged"
    }

    private static func isSubagentTool(payload: [String: String]) -> Bool {
        let candidates = [
            payload["mcp_tool"],
            payload["tool"],
            payload["name"],
        ]
        return candidates.contains { candidate in
            let normalized = (candidate ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return normalized.contains("subagent_")
        }
    }

    private static func isLaunchAckText(_ raw: String?) -> Bool {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.hasPrefix("ok — subagent")
            || normalized.hasPrefix("ok - subagent")
            || (normalized.contains("subagent") && normalized.contains("launched"))
    }

    private static func normalizedLaunchSource(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let lower = text.lowercased()
        let completedSuffixes = [
            " — completed",
            " - completed",
        ]
        for suffix in completedSuffixes where lower.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
