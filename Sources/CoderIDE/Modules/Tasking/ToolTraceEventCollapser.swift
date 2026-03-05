import Foundation

enum ToolTraceEventCollapser {
    static func collapseSupersededToolStates(_ input: [ToolTraceEvent]) -> [ToolTraceEvent] {
        var latestByOperation: [String: ToolTraceEvent] = [:]
        var passthrough: [ToolTraceEvent] = []

        for event in input {
            guard let operationKey = collapseOperationKey(for: event) else {
                passthrough.append(event)
                continue
            }
            latestByOperation[operationKey] = event
        }

        let collapsed = Array(latestByOperation.values)
        let merged = passthrough + collapsed
        return merged.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }
    }

    static func collapseOperationKey(for event: ToolTraceEvent) -> String? {
        if let toolCallId = nonEmpty(
            event.payload["tool_call_id"]
                ?? event.payload["toolCallId"]
                ?? event.payload["call_id"]
                ?? event.payload["callId"]
        ) {
            return "tool_call_id:\(toolCallId)"
        }

        if let eventId = nonEmpty(event.payload["id"]) {
            return "event_id:\(eventId)"
        }

        if let queryId = nonEmpty(event.payload["queryId"] ?? event.payload["query_id"]) {
            return "query_id:\(queryId)"
        }

        if let groupId = nonEmpty(event.groupId ?? event.payload["group_id"] ?? event.payload["groupId"]) {
            // Avoid collapsing swarm lanes by bare group id; they represent
            // long-lived streams and collapsing would hide intermediate steps.
            if groupId.lowercased().hasPrefix("swarm-") {
                return nil
            }
            return "group_id:\(groupId)"
        }

        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
