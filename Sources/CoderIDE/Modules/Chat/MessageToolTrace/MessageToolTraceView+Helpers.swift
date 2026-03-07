import SwiftUI

extension MessageToolTraceView {
    func payloadValue(_ payload: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = nonEmpty(payload[key]) {
                return value
            }
        }
        return nil
    }

    func compactDiffChunk(for change: ToolTraceFileChange) -> String? {
        if let payloadPreview = nonEmpty(change.diffPreview) {
            return payloadPreview
        }
        if let cached = filePreviewByEventId[change.id],
           case .diff(let text) = cached,
           let nonEmptyText = nonEmpty(text) {
            return nonEmptyText
        }
        return nil
    }

    func editLineSummary(for event: ToolTraceEvent) -> String? {
        guard let counters = editLineCounters(for: event) else { return nil }
        return "+\(counters.added) -\(counters.removed)"
    }

    func editLineCounters(for event: ToolTraceEvent) -> (added: Int, removed: Int)? {
        let payload = event.payload
        let hasFileHints = ToolTraceFileChangeMapper.isFileChangeEvent(event)
            || nonEmpty(payload["path"]) != nil
            || nonEmpty(payload["file"]) != nil
            || nonEmpty(payload["diffPreview"]) != nil
            || nonEmpty(payload["diff"]) != nil
        guard hasFileHints else { return nil }

        let explicitAdded = parseInt(payload: payload, keys: [
            "linesAdded", "additions", "insertions", "added",
        ]) ?? 0
        let explicitRemoved = parseInt(payload: payload, keys: [
            "linesRemoved", "deletions", "removed",
        ]) ?? 0

        if explicitAdded > 0 || explicitRemoved > 0 {
            return (explicitAdded, explicitRemoved)
        }

        if let diff = nonEmpty(
            payload["diffPreview"]
                ?? payload["diff"]
                ?? payload["patch"]
                ?? payload["unified_diff"]
                ?? payload["changes_preview"]
        ) {
            return diffLineCounts(from: diff)
        }

        if let summary = nonEmpty(
            payload["detail"]
                ?? payload["output"]
                ?? payload["result"]
                ?? payload["stdout"]
        ),
            let summaryCounters = replacementSummaryLineCounts(from: summary) {
            return summaryCounters
        }

        if ToolTraceFileChangeMapper.isFileChangeEvent(event) {
            return (0, 0)
        }
        return nil
    }

    func diffLineCounts(from diff: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                continue
            }
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }
        return (max(0, added), max(0, removed))
    }

    func parseInt(payload: [String: String], keys: [String]) -> Int? {
        for key in keys {
            let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            if let value = Int(raw) {
                return value
            }
        }
        return nil
    }

    private static let replacementSummaryRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "\\((\\d+)\\s+lines?\\s*(?:->|\u{2192})\\s*(\\d+)\\s+lines?\\)",
                options: [.caseInsensitive])
        } catch {
            assertionFailure("Invalid hardcoded regex – \(error)")
            do { return try NSRegularExpression(pattern: "", options: []) }
            catch { preconditionFailure("Empty NSRegularExpression pattern must always compile") }
        }
    }()

    func replacementSummaryLineCounts(from summary: String) -> (added: Int, removed: Int)? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = Self.replacementSummaryRegex.firstMatch(in: trimmed, options: [], range: range),
              let oldRange = Range(match.range(at: 1), in: trimmed),
              let newRange = Range(match.range(at: 2), in: trimmed),
              let oldLines = Int(trimmed[oldRange]),
              let newLines = Int(trimmed[newRange]) else {
            return nil
        }
        return (added: max(0, newLines), removed: max(0, oldLines))
    }

    func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func truncatePreview(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end])
            + "\n\n... diff truncated (\(text.count - limit) characters hidden)"
    }

    func pluralized(_ noun: String, count: Int, plural: String? = nil) -> String {
        count == 1 ? noun : (plural ?? "\(noun)s")
    }
}
