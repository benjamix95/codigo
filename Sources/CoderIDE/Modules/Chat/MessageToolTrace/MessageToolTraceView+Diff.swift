import SwiftUI

extension MessageToolTraceView {
    // MARK: - Diff Rendering

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

    // MARK: - Helpers

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

    static func isErrorType(_ event: ToolTraceEvent) -> Bool {
        let type = event.type.lowercased()
        let status = (event.payload["status"] ?? "").lowercased()
        if Self.hardErrorTypes.contains(type) || type.contains("error") {
            return true
        }
        return status == "error" || status == "fatal"
    }

    static func isWarningType(_ event: ToolTraceEvent) -> Bool {
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
                return String(text.prefix(120))
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
}
