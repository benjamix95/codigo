import Foundation

extension EventNormalizer {
    static func normalizeInstantGrep(grep: InstantGrepResult, payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let reportedCount = Int(payload["matchesCount"] ?? payload["matches_count"] ?? "") ?? grep.matchesCount
        let parsedPreviewCount = grep.matches.count
        let drift = abs(reportedCount - parsedPreviewCount)
        var enrichedPayload = payload
        enrichedPayload["matches_count_reported"] = "\(reportedCount)"
        enrichedPayload["matches_count_parsed_preview"] = "\(parsedPreviewCount)"
        enrichedPayload["matches_count_drift"] = "\(drift)"

        return [
            .instantGrep(grep),
            .taskActivity(TaskActivity(
                type: "instant_grep",
                title: "Instant Grep • \(grep.query)",
                detail: "\(grep.matchesCount) results",
                payload: enrichedPayload,
                timestamp: timestamp,
                phase: .searching,
                isRunning: false
            ))
        ]
    }
}
