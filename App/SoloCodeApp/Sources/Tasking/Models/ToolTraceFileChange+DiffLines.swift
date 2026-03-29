import SwiftUI

enum ToolTraceFileChangeDiffLineStyle: Equatable {
    case addition
    case removal
    case hunk
    case metadata
    case context

    var color: Color {
        switch self {
        case .addition:
            return DesignSystem.Colors.success
        case .removal:
            return DesignSystem.Colors.error
        case .hunk:
            return DesignSystem.Colors.planColor.opacity(0.92)
        case .metadata:
            return DesignSystem.Colors.textTertiary
        case .context:
            return DesignSystem.Colors.textSecondary
        }
    }
}

struct ToolTraceFileChangeDiffLine: Equatable, Identifiable {
    let id: Int
    let text: String
    let style: ToolTraceFileChangeDiffLineStyle
}

extension ToolTraceFileChange {
    func fullPreviewDiffLines() -> [ToolTraceFileChangeDiffLine] {
        guard let preview = fullPreviewText else { return [] }
        let rawLines = preview.split(separator: "\n", omittingEmptySubsequences: false)

        return rawLines.enumerated().map { index, rawLine in
            let line = String(rawLine)
            return ToolTraceFileChangeDiffLine(
                id: index,
                text: line,
                style: Self.diffLineStyle(for: line)
            )
        }
    }

    func compactPreviewDiffLines(limit: Int = 4) -> [ToolTraceFileChangeDiffLine] {
        guard limit > 0 else { return [] }
        return compactPreviewLines(limit: limit).enumerated().map { index, line in
            ToolTraceFileChangeDiffLine(
                id: index,
                text: line,
                style: Self.diffLineStyle(for: line)
            )
        }
    }

    private static func diffLineStyle(for line: String) -> ToolTraceFileChangeDiffLineStyle {
        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return .addition
        }
        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return .removal
        }
        if line.hasPrefix("@@") {
            return .hunk
        }
        if line.hasPrefix("diff --git")
            || line.hasPrefix("index ")
            || line.hasPrefix("---")
            || line.hasPrefix("+++") {
            return .metadata
        }
        return .context
    }
}
