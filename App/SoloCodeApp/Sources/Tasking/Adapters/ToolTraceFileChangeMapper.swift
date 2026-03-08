import Foundation

enum ToolTraceFileChangeMapper {
    static func isFileChangeEvent(_ event: ToolTraceEvent) -> Bool {
        isFileChangeType(rawType: event.type, payload: event.payload)
    }

    static func isFileChangeActivity(_ activity: TaskActivity) -> Bool {
        isFileChangeType(rawType: activity.type, payload: activity.payload)
    }

    static func from(event: ToolTraceEvent) -> ToolTraceFileChange? {
        guard isFileChangeEvent(event) else { return nil }
        return build(
            id: event.id,
            payload: event.payload,
            title: event.title,
            timestamp: event.timestamp,
            sequence: event.sequence,
            isRunning: event.isRunning
        )
    }

    static func from(activity: TaskActivity) -> ToolTraceFileChange? {
        guard isFileChangeActivity(activity) else { return nil }
        return build(
            id: activity.id,
            payload: activity.payload,
            title: activity.title,
            timestamp: activity.timestamp,
            sequence: 0,
            isRunning: activity.isRunning
        )
    }

    static func collect(from events: [ToolTraceEvent]) -> [ToolTraceFileChange] {
        let ordered: [ToolTraceEvent]
        if areEventsAlreadyOrdered(events) {
            ordered = events
        } else {
            ordered = events.sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.timestamp < $1.timestamp
            }
        }

        var byKey: [String: ToolTraceFileChange] = [:]
        var keyOrder: [String] = []
        for event in ordered {
            guard let change = from(event: event) else { continue }
            let key = stableKey(for: event, fallbackPath: change.path)
            if let existing = byKey[key] {
                byKey[key] = prefer(existing: existing, incoming: change)
            } else {
                byKey[key] = change
                keyOrder.append(key)
            }
        }
        return keyOrder.compactMap { byKey[$0] }
    }

    static func areEventsAlreadyOrdered(_ events: [ToolTraceEvent]) -> Bool {
        guard events.count > 1 else { return true }
        var previous = events[0]
        for current in events.dropFirst() {
            if current.sequence < previous.sequence { return false }
            if current.sequence == previous.sequence, current.timestamp < previous.timestamp {
                return false
            }
            previous = current
        }
        return true
    }
}
