import SwiftUI

/// Clean, Cursor-style outcome card for the review panel chat.
/// Shows the final review result with a status badge, summary,
/// metric pills, and optional mermaid diagram.
struct ReviewPanelChatOutcomeView: View {
    let section: ReviewPanelChatStructuredSection
    let accent: Color

    private var statusLine: String? {
        section.lines.first
    }

    private var summaryLines: [String] {
        guard section.lines.count > 1 else { return [] }
        return Array(section.lines.dropFirst()).filter { !isMetricLine($0) }
    }

    private var metricPills: [(label: String, value: String)] {
        section.lines.compactMap { line in
            guard isMetricLine(line) else { return nil }
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            let label = parts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "- ", with: "")
            let value = parts.dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (label, value)
        }
    }

    private func isMetricLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let metricPrefixes = [
            "verified", "false_positive", "fp", "applied",
            "patches", "pr", "merged", "findings",
            "- verified", "- false", "- fp", "- applied",
            "- patches", "- pr", "- merged", "- findings"
        ]
        let lower = trimmed.lowercased()
        return metricPrefixes.contains(where: { lower.hasPrefix($0) })
            && trimmed.contains(":")
    }

    private var statusIcon: String {
        guard let status = statusLine?.lowercased() else {
            return "checkmark.seal"
        }
        if status.contains("pass") || status.contains("clean")
            || status.contains("success")
        {
            return "checkmark.seal.fill"
        }
        if status.contains("fail") || status.contains("critical") {
            return "xmark.seal.fill"
        }
        if status.contains("warning") || status.contains("action") {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal"
    }

    private var statusColor: Color {
        guard let status = statusLine?.lowercased() else { return accent }
        if status.contains("pass") || status.contains("clean")
            || status.contains("success")
        {
            return Color(red: 0.30, green: 0.78, blue: 0.45)
        }
        if status.contains("fail") || status.contains("critical") {
            return Color(red: 0.92, green: 0.34, blue: 0.34)
        }
        if status.contains("warning") || status.contains("action") {
            return Color(red: 0.95, green: 0.72, blue: 0.28)
        }
        return accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBadge
            if !summaryLines.isEmpty {
                summaryBlock
            }
            if !metricPills.isEmpty {
                metricsRow
            }
        }
        .padding(12)
        .background(outcomeFill)
        .overlay(outcomeBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(statusLine ?? "Review Complete")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        MarkdownContentView(
            content: summaryLines.joined(separator: "\n"),
            context: nil,
            onFileClicked: { _ in },
            isStreaming: false,
            normalizeDisplayLayout: false
        )
    }

    // MARK: - Metrics

    private var metricsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(
                Array(metricPills.enumerated()),
                id: \.offset
            ) { _, pill in
                metricPill(label: pill.label, value: pill.value)
            }
        }
    }

    private func metricPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(
                    size: 8.5,
                    weight: .bold,
                    design: .monospaced
                ))
                .foregroundStyle(statusColor.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(statusColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(statusColor.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: - Background

    private var outcomeFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        statusColor.opacity(0.08),
                        Color.black.opacity(0.26),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var outcomeBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(statusColor.opacity(0.22), lineWidth: 0.6)
    }
}

// MARK: - Flow Layout (for metric pills)

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = arrange(
            proposal: proposal,
            subviews: subviews
        )
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(
            proposal: ProposedViewSize(bounds.size),
            subviews: subviews
        )
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        let size: CGSize
        let positions: [CGPoint]
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}
