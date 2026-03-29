import Foundation

extension ToolTraceFileChange {
    var fullPreviewText: String? {
        [
            diffPreview,
            rawOutput,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    func compactPreviewLines(limit: Int = 4) -> [String] {
        guard limit > 0 else { return [] }
        guard let previewSource = fullPreviewText else { return [] }

        let ignoredPrefixes = [
            "diff --git",
            "index ",
            "---",
            "+++",
            "@@",
        ]

        let lines = previewSource
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return !ignoredPrefixes.contains { prefix in line.hasPrefix(prefix) }
            }

        return Array(lines.prefix(limit))
    }

    func compactPreviewText(limit: Int = 4) -> String? {
        let lines = compactPreviewLines(limit: limit)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    var hasCompactPreview: Bool {
        compactPreviewText() != nil
    }

    var hasFullPreview: Bool {
        fullPreviewText != nil
    }
}

extension Array where Element == ToolTraceFileChange {
    func latestChange() -> ToolTraceFileChange? {
        self.max { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
    }

    func latestPreviewableChange() -> ToolTraceFileChange? {
        filter(\.hasCompactPreview).latestChange()
    }
}
