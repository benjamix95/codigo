import Foundation

func shouldBufferOperationalRawEventUntilNarrative(
    rawType: String,
    payload: [String: String]
) -> Bool {
    let type = rawType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if type.isEmpty { return false }

    let nonBufferedTypes: Set<String> = [
        "started", "turn_started", "turn_completed", "policy_ack", "assistant_update",
        "reasoning", "error", "tool_validation_error", "tool_execution_error",
        "tool_timeout", "permission_denied", "usage",
    ]
    if nonBufferedTypes.contains(type) || type.hasPrefix("reasoning") || type.hasPrefix("thinking") {
        return false
    }

    if type == "mcp_tool_call" {
        let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "functions.", with: "")
            .replacingOccurrences(of: "function.", with: "")
        if tool == "coderide_policy_ack" || tool == "policy_ack" {
            return false
        }
    }

    if type == "mcp_tool_call" || type == "command_execution" || type == "bash" {
        return true
    }
    if ["agent", "read", "read_range", "grep", "glob", "codebase_search",
        "find_symbol", "find_references", "file_outline", "list_dir"].contains(type) {
        return true
    }
    if type.hasPrefix("web_search")
        || type.hasPrefix("web_fetch")
        || type.hasPrefix("todo_")
        || type.hasPrefix("plan_")
        || ["search", "semantic_search", "instant_grep", "file_change", "edit", "skill_invocation"].contains(type)
    {
        return true
    }

    return ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload)
}

struct ConversationFlowTextFlushPolicy {
    let minCharsBeforeRawFlush = 192
    let maxLatencyBeforeRawFlushMs = 64

    func shouldFlushBeforeRawEvent(
        isDirty: Bool,
        renderedTextCount: Int,
        lastFlushedLength: Int,
        lastFlushAt: Date,
        now: Date = .now
    ) -> Bool {
        guard isDirty else { return false }
        let charsSinceLastFlush = max(0, renderedTextCount - lastFlushedLength)
        if charsSinceLastFlush >= minCharsBeforeRawFlush {
            return true
        }
        let latencyMs = Int(now.timeIntervalSince(lastFlushAt) * 1000)
        return latencyMs >= maxLatencyBeforeRawFlushMs
    }
}

struct ConversationFlowRawEventBatch {
    private var events: [(String, [String: String])] = []

    var isEmpty: Bool { events.isEmpty }

    mutating func append(_ value: (String, [String: String])) {
        events.append(value)
    }

    mutating func append(contentsOf values: [(String, [String: String])]) {
        events.append(contentsOf: values)
    }

    mutating func drain() -> [(String, [String: String])] {
        let pending = events
        events.removeAll(keepingCapacity: true)
        return pending
    }
}

extension MainChatRuntimeSnapshotBridge {
    var currentPollTimeoutSeconds: Int? {
        guard let directStream else { return nil }
        return directStream.hasReceivedAnyEvent ? directStream.activityTimeoutSec : directStream.firstEventTimeoutSec
    }
}
