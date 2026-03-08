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
        if lower.hasPrefix("{") && lower.contains("\"task\"") { return nil }

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
