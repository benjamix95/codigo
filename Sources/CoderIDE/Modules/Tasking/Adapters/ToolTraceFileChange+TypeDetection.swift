import Foundation

extension ToolTraceFileChangeMapper {
    static func detectDiffSource(
        payload: [String: String],
        explicitAdded: Int,
        explicitRemoved: Int,
        diffPreview: String?
    ) -> ToolTraceFileChangeDiffSource {
        let rawSource = firstNonEmpty(payload: payload, keys: [
            "diff_source", "counter_source", "source",
        ])?.lowercased() ?? ""
        if rawSource.contains("git_head_fallback") || rawSource.contains("git_fallback") {
            return .gitFallback
        }
        if rawSource == "payload" || rawSource == "mcp" {
            return .payload
        }
        if explicitAdded > 0 || explicitRemoved > 0 {
            return .payload
        }
        if let diffPreview, !diffPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .payload
        }
        return .unknown
    }

    static let replacementSummaryRegex = try! NSRegularExpression(
        pattern: "\\((\\d+)\\s+lines?\\s*(?:->|→)\\s*(\\d+)\\s+lines?\\)",
        options: [.caseInsensitive]
    )

    static func parseReplacementSummaryCounts(from summary: String) -> (added: Int, removed: Int)? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = replacementSummaryRegex.firstMatch(in: trimmed, options: [], range: range),
              let oldRange = Range(match.range(at: 1), in: trimmed),
              let newRange = Range(match.range(at: 2), in: trimmed),
              let oldCount = Int(trimmed[oldRange]),
              let newCount = Int(trimmed[newRange]) else {
            return nil
        }
        return (added: max(0, newCount), removed: max(0, oldCount))
    }

    static func isFileChangeType(rawType: String, payload: [String: String]) -> Bool {
        let normalized = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if fileChangeTypes.contains(normalized) {
            return true
        }
        let normalizedTool = normalizedToolIdentifier(payload["tool"] ?? payload["name"] ?? "")
        if fileChangeTools.contains(normalizedTool) {
            return true
        }

        let hasPathHint = firstNonEmpty(payload: payload, keys: [
            "path", "file", "file_path", "relative_path", "target_path",
        ]) != nil
        let hasDiffHint = firstNonEmpty(payload: payload, keys: [
            "diffPreview", "diff", "patch", "unified_diff", "changes_preview",
            "old_string", "new_string", "linesAdded", "linesRemoved", "additions", "deletions",
        ]) != nil
        return hasPathHint && hasDiffHint
    }

    static let fileChangeTypes: Set<String> = [
        "file_change",
        "edit",
        "str_replace",
        "regex_replace",
        "write",
        "create_file",
        "delete_file",
        "parallel_apply",
        "apply_patch",
        "rename_symbol",
        "find_and_replace_all",
        "undo_edit",
        "multi_edit",
        "multiedit",
    ]

    static let fileChangeTools: Set<String> = [
        "edit",
        "str_replace",
        "regex_replace",
        "write",
        "create_file",
        "delete_file",
        "parallel_apply",
        "apply_patch",
        "rename_symbol",
        "find_and_replace_all",
        "undo_edit",
        "multi_edit",
        "multiedit",
    ]

    static func firstNonEmpty(payload: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func normalizedToolIdentifier(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else { return "" }
        let parts = normalized
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return normalized }
        return last
    }
}
