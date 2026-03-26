import SwiftUI

extension MessageToolTraceView {
    func buildDiffAttributed(_ diff: String) -> AttributedString {
        let maxLines = 250
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        var result = AttributedString()
        for (i, line) in lines.prefix(maxLines).enumerated() {
            if i > 0 { result += AttributedString("\n") }
            var attr = AttributedString(String(line))
            attr.foregroundColor = nsDiffLineColor(String(line))
            result += attr
        }
        if lines.count > maxLines {
            var truncation = AttributedString("\n... \(lines.count - maxLines) more lines")
            truncation.foregroundColor = NSColor(DesignSystem.Colors.textTertiary)
            result += truncation
        }
        return result
    }

    func nsDiffLineColor(_ line: String) -> NSColor {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return NSColor(DesignSystem.Colors.textTertiary)
        }
        if line.hasPrefix("@@") {
            return NSColor(DesignSystem.Colors.info.opacity(0.7))
        }
        if line.hasPrefix("+") {
            return NSColor(DesignSystem.Colors.success)
        }
        if line.hasPrefix("-") {
            return NSColor(DesignSystem.Colors.error)
        }
        return NSColor(DesignSystem.Colors.textSecondary)
    }

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
            return (try? NSRegularExpression(pattern: "", options: [])) ?? NSRegularExpression()
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

    func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    func shortenedPath(_ path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        if components.count <= 2 { return path }
        let last2 = components.suffix(2).joined(separator: "/")
        return ".../" + last2
    }

    nonisolated static func isErrorType(_ event: ToolTraceEvent) -> Bool {
        let type = event.type.lowercased()
        let status = (event.payload["status"] ?? "").lowercased()
        if Self.hardErrorTypes.contains(type) || type.contains("error") {
            return true
        }
        return status == "error" || status == "fatal"
    }

    nonisolated static func isWarningType(_ event: ToolTraceEvent) -> Bool {
        guard !isErrorType(event) else { return false }
        let type = event.type.lowercased()
        let status = (event.payload["status"] ?? "").lowercased()
        let severity = (event.payload["severity"] ?? "").lowercased()
        if status == "failed" || status == "warning" {
            return true
        }
        if severity == "warning" {
            return true
        }
        return type.contains("failed")
    }

    func compactDetail(for event: ToolTraceEvent) -> String? {
        if let lineSummary = editLineSummary(for: event) {
            return lineSummary
        }
        let type = event.type.lowercased()
        let isSearchLike = type.contains("grep") || type.contains("search") || type == "instant_grep"
        let candidates: [String?]
        if isSearchLike {
            candidates = [
                event.payload["query"],
                event.payload["command"],
                event.detail,
                event.payload["path"],
                event.payload["file"],
            ]
        } else {
            candidates = [
                event.detail,
                event.payload["command"],
                event.payload["query"],
                event.payload["path"],
                event.payload["file"],
                event.payload["tool"],
                event.payload["mcp_tool"],
                event.payload["mcpTool"],
                event.payload["mcp_server"],
                event.payload["mcpServer"],
                event.payload["server_id"],
                event.payload["serverId"],
            ]
        }
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return UserFacingToolTraceRedaction.compactTraceDetail(from: text)
            }
        }
        return nil
    }

    func compactDiffPreview(fileChanges: [ToolTraceFileChange]) -> String? {
        var sections: [String] = []
        for change in fileChanges {
            guard let chunk = compactDiffChunk(for: change) else { continue }
            let path = nonEmpty(change.path) ?? change.basename
            sections.append("### \(change.kind.displayTitle) \(path)\n\(chunk)")
        }
        guard !sections.isEmpty else { return nil }
        return truncatePreview(sections.joined(separator: "\n\n"), limit: 24_000)
    }

    func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func truncatePreview(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end])
            + "\n\n... diff troncato (\(text.count - limit) caratteri nascosti)"
    }

    func pluralized(_ noun: String, count: Int, plural: String? = nil) -> String {
        count == 1 ? noun : (plural ?? "\(noun)s")
    }
}
