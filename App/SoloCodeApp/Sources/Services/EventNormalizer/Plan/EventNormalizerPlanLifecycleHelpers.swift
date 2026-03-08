import Foundation

extension EventNormalizer {
    static func normalizePlanOutcome(_ raw: String?) -> String {
        let normalized = (raw ?? "done").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "done", "failed", "cancelled": return normalized
        default: return "done"
        }
    }

    static func normalizedConversationId(from payload: [String: String]) -> String? {
        normalizedConversationId(payload["conversation_id"] ?? payload["conversationId"])
    }

    static func normalizedConversationId(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func nonEmptyTrimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func invalidPlanPayloadActivity(
        type: String,
        payload: [String: String],
        timestamp: Date
    ) -> NormalizedEvent {
        .taskActivity(TaskActivity(
            type: type,
            title: type,
            detail: "Invalid or missing plan payload",
            payload: payload,
            timestamp: timestamp,
            phase: .planning,
            isRunning: false
        ))
    }
}
