import Foundation

enum SwarmLivePresentation {
    private static let genericStatuses: Set<String> = [
        "completed", "done", "failed", "idle", "in_progress", "pending", "queued", "running", "started", "working...",
    ]

    static func normalizedSubtitleText(
        _ raw: String?,
        excluding excludedText: String? = nil,
        maxLength: Int = 120
    ) -> String? {
        let text = (raw ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if genericStatuses.contains(lower) { return nil }
        if lower.hasPrefix("mcp call") && lower.contains("subagent_") { return nil }
        if lower.hasPrefix("mcp__") { return nil }
        if lower.contains("__coderide__") { return nil }
        if lower.hasPrefix("subagent_") { return nil }
        if lower.hasPrefix("{") && lower.contains("\"task\"") { return nil }
        if lower.hasPrefix("sa-") { return nil }
        if lower.hasPrefix("swarm-sa-") { return nil }
        if lower.hasPrefix("swarm-claude-") { return nil }
        if lower.hasPrefix("swarm-codex-") { return nil }
        if lower.hasPrefix("swarm ") { return nil }
        if lower.hasPrefix("swarm-") && lower.count > 20 { return nil }
        if lower.hasPrefix("explorer-toolu") || lower.hasPrefix("coder-toolu") ||
           lower.hasPrefix("debugger-toolu") || lower.hasPrefix("reviewer-toolu") ||
           lower.hasPrefix("agent-toolu") { return nil }
        // Filter raw tool_use_id fragments
        if lower.contains("toolu_") { return nil }

        let excluded = (excludedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !excluded.isEmpty && text.caseInsensitiveCompare(excluded) == .orderedSame {
            return nil
        }

        return String(text.prefix(maxLength))
    }

    static func latestMeaningfulLiveLine(
        from text: String,
        excluding excludedText: String? = nil,
        maxLength: Int = 120
    ) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if let normalized = normalizedSubtitleText(
                line,
                excluding: excludedText,
                maxLength: maxLength
            ) {
                return normalized
            }
        }
        return nil
    }
}
