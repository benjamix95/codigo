import Foundation

enum ToolTraceFileChangeKind: String, CaseIterable {
    case created
    case edited
    case deleted
    case unknown

    var displayTitle: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .deleted: return "Deleted"
        case .unknown: return "Edited"
        }
    }
}

struct ToolTraceFileChange: Identifiable, Hashable {
    let eventId: UUID
    let path: String?
    let basename: String
    let kind: ToolTraceFileChangeKind
    let added: Int
    let removed: Int
    let diffPreview: String?
    let rawOutput: String?
    let sequence: Int
    let timestamp: Date
    let isRunning: Bool

    var id: UUID { eventId }
}

enum ToolTraceFileChangeMapper {
    static func isFileChangeEvent(_ event: ToolTraceEvent) -> Bool {
        let normalized = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "file_change" || normalized == "edit"
    }

    static func isFileChangeActivity(_ activity: TaskActivity) -> Bool {
        let normalized = activity.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "file_change" || normalized == "edit"
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
        let ordered = events.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }

        var byKey: [String: ToolTraceFileChange] = [:]
        for event in ordered {
            guard let change = from(event: event) else { continue }
            let key = stableKey(for: event, fallbackPath: change.path)
            if let existing = byKey[key] {
                byKey[key] = prefer(existing: existing, incoming: change)
            } else {
                byKey[key] = change
            }
        }
        return byKey.values.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }
    }

    private static func build(
        id: UUID,
        payload: [String: String],
        title: String,
        timestamp: Date,
        sequence: Int,
        isRunning: Bool
    ) -> ToolTraceFileChange {
        let path = normalizedPath(
            firstNonEmpty(payload: payload, keys: [
                "path", "file", "file_path", "relative_path", "target_path",
            ])
        )
        let basename = path.map { ($0 as NSString).lastPathComponent }.flatMap {
            $0.isEmpty ? nil : $0
        } ?? "file"

        let kind = detectKind(payload: payload, title: title)
        let added = parseInt(payload: payload, keys: [
            "linesAdded", "additions", "insertions", "added",
        ]) ?? 0
        let removed = parseInt(payload: payload, keys: [
            "linesRemoved", "deletions", "removed",
        ]) ?? 0
        let diffPreview = firstNonEmpty(payload: payload, keys: [
            "diffPreview", "diff", "patch", "unified_diff", "changes_preview",
        ])
        let rawOutput = firstNonEmpty(payload: payload, keys: [
            "output", "result", "stdout",
        ])

        return ToolTraceFileChange(
            eventId: id,
            path: path,
            basename: basename,
            kind: kind,
            added: max(0, added),
            removed: max(0, removed),
            diffPreview: diffPreview,
            rawOutput: rawOutput,
            sequence: sequence,
            timestamp: timestamp,
            isRunning: isRunning
        )
    }

    private static func stableKey(for event: ToolTraceEvent, fallbackPath: String?) -> String {
        let payload = event.payload
        let source = firstNonEmpty(payload: payload, keys: [
            "id", "tool_call_id", "group_id", "path", "file", "relative_path", "target_path",
        ]) ?? fallbackPath ?? event.id.uuidString
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prefer(existing: ToolTraceFileChange, incoming: ToolTraceFileChange)
        -> ToolTraceFileChange
    {
        if existing.isRunning && !incoming.isRunning { return incoming }
        if !existing.isRunning && incoming.isRunning { return existing }
        if incoming.sequence >= existing.sequence { return incoming }
        return existing
    }

    private static func detectKind(payload: [String: String], title: String) -> ToolTraceFileChangeKind {
        let operationRaw = firstNonEmpty(payload: payload, keys: [
            "change_type", "operation", "action", "edit_type",
        ])?.lowercased() ?? ""
        if isCreated(operationRaw) { return .created }
        if isDeleted(operationRaw) { return .deleted }
        if isEdited(operationRaw) { return .edited }

        let toolRaw = firstNonEmpty(payload: payload, keys: [
            "tool", "name",
        ])?.lowercased() ?? ""
        if isCreated(toolRaw) { return .created }
        if isDeleted(toolRaw) { return .deleted }
        if isEdited(toolRaw) { return .edited }

        let lowerTitle = title.lowercased()
        if lowerTitle.hasPrefix("created ") { return .created }
        if lowerTitle.hasPrefix("deleted ") { return .deleted }
        if lowerTitle.hasPrefix("edited ") || lowerTitle.hasPrefix("edit ") {
            return .edited
        }

        return .edited
    }

    private static func isCreated(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        return value.contains("create")
            || value.contains("new")
            || value == "a"
            || value == "add"
            || value == "added"
            || value == "create_file"
    }

    private static func isDeleted(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        return value.contains("delete")
            || value.contains("remove")
            || value == "d"
            || value == "deleted"
    }

    private static func isEdited(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        return value.contains("edit")
            || value.contains("modify")
            || value.contains("update")
            || value.contains("write")
            || value.contains("replace")
            || value == "m"
            || value == "modified"
    }

    private static func normalizedPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseInt(payload: [String: String], keys: [String]) -> Int? {
        for key in keys {
            let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            if let value = Int(raw) { return value }
        }
        return nil
    }

    private static func firstNonEmpty(payload: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
