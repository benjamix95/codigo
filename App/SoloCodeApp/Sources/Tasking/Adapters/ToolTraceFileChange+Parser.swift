import Foundation

extension ToolTraceFileChangeMapper {
    static func build(
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
        let explicitAdded = parseInt(payload: payload, keys: [
            "linesAdded", "additions", "insertions", "added",
        ]) ?? 0
        let explicitRemoved = parseInt(payload: payload, keys: [
            "linesRemoved", "deletions", "removed",
        ]) ?? 0
        let diffPreview = firstNonEmpty(payload: payload, keys: [
            "diffPreview", "diff", "patch", "unified_diff", "changes_preview",
        ])
        let replacementSummary = firstNonEmpty(payload: payload, keys: [
            "detail", "output", "result", "stdout",
        ])
        let inferred = inferCounters(
            added: explicitAdded,
            removed: explicitRemoved,
            diffPreview: diffPreview,
            replacementSummary: replacementSummary
        )
        let diffSource = detectDiffSource(
            payload: payload,
            explicitAdded: explicitAdded,
            explicitRemoved: explicitRemoved,
            diffPreview: diffPreview
        )
        let rawOutput = firstNonEmpty(payload: payload, keys: [
            "output", "result", "stdout",
        ])

        return ToolTraceFileChange(
            eventId: id,
            path: path,
            basename: basename,
            kind: kind,
            added: max(0, inferred.added),
            removed: max(0, inferred.removed),
            diffPreview: diffPreview,
            rawOutput: rawOutput,
            diffSource: diffSource,
            sequence: sequence,
            timestamp: timestamp,
            isRunning: isRunning
        )
    }

    static func stableKey(for event: ToolTraceEvent, fallbackPath: String?) -> String {
        let payload = event.payload
        let source = firstNonEmpty(payload: payload, keys: [
            "id", "tool_call_id", "group_id", "path", "file", "relative_path", "target_path",
        ]) ?? fallbackPath ?? event.id.uuidString
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func prefer(existing: ToolTraceFileChange, incoming: ToolTraceFileChange)
        -> ToolTraceFileChange
    {
        let preferred: ToolTraceFileChange
        let fallback: ToolTraceFileChange

        if existing.isRunning && !incoming.isRunning {
            preferred = incoming
            fallback = existing
        } else if !existing.isRunning && incoming.isRunning {
            preferred = existing
            fallback = incoming
        } else if incoming.sequence >= existing.sequence {
            preferred = incoming
            fallback = existing
        } else {
            preferred = existing
            fallback = incoming
        }

        return merge(preferred: preferred, fallback: fallback)
    }

    private static func merge(
        preferred: ToolTraceFileChange,
        fallback: ToolTraceFileChange
    ) -> ToolTraceFileChange {
        ToolTraceFileChange(
            eventId: preferred.eventId,
            path: preferred.path ?? fallback.path,
            basename: preferred.basename == "file" ? fallback.basename : preferred.basename,
            kind: preferred.kind == .unknown ? fallback.kind : preferred.kind,
            added: preferred.added == 0 ? fallback.added : preferred.added,
            removed: preferred.removed == 0 ? fallback.removed : preferred.removed,
            diffPreview: preferred.diffPreview ?? fallback.diffPreview,
            rawOutput: preferred.rawOutput ?? fallback.rawOutput,
            diffSource: preferred.diffSource == .unknown ? fallback.diffSource : preferred.diffSource,
            sequence: preferred.sequence,
            timestamp: preferred.timestamp,
            isRunning: preferred.isRunning
        )
    }

    static func detectKind(payload: [String: String], title: String) -> ToolTraceFileChangeKind {
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

    static func isCreated(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        return value.contains("create")
            || value.contains("new")
            || value == "a"
            || value == "add"
            || value == "added"
            || value == "create_file"
    }

    static func isDeleted(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        return value.contains("delete")
            || value.contains("remove")
            || value == "d"
            || value == "deleted"
    }

    static func isEdited(_ text: String) -> Bool {
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

    static func normalizedPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseInt(payload: [String: String], keys: [String]) -> Int? {
        for key in keys {
            let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            if let value = Int(raw) { return value }
        }
        return nil
    }

    static func inferCounters(
        added: Int,
        removed: Int,
        diffPreview: String?,
        replacementSummary: String?
    ) -> (added: Int, removed: Int) {
        guard added == 0, removed == 0 else {
            return (added, removed)
        }

        if let diffPreview {
            let trimmed = diffPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                var inferredAdded = 0
                var inferredRemoved = 0
                for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
                    if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                        continue
                    }
                    if line.hasPrefix("+") {
                        inferredAdded += 1
                    } else if line.hasPrefix("-") {
                        inferredRemoved += 1
                    }
                }
                return (inferredAdded, inferredRemoved)
            }
        }

        if let replacementSummary,
           let summaryCounters = parseReplacementSummaryCounts(from: replacementSummary) {
            return summaryCounters
        }

        return (added, removed)
    }
}
