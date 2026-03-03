import Foundation

extension EventNormalizer {
    static func normalizeInstantGrep(grep: InstantGrepResult, payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        return [
            .instantGrep(grep),
            .taskActivity(TaskActivity(
                type: "instant_grep",
                title: "Instant Grep • \(grep.query)",
                detail: "\(grep.matchesCount) results",
                payload: payload,
                timestamp: timestamp,
                phase: .searching,
                isRunning: false
            ))
        ]
    }
}
