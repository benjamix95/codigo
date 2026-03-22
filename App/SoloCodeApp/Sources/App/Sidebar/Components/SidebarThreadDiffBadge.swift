import SwiftUI

/// Compact inline diff stats badge showing +added / -removed lines.
struct SidebarThreadDiffBadge: View {
    let linesAdded: Int
    let linesRemoved: Int

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxs + 1) {
            if linesAdded > 0 {
                Text("+\(formattedCount(linesAdded))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
            }
            if linesRemoved > 0 {
                Text("-\(formattedCount(linesRemoved))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
        }
    }

    private func formattedCount(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.0fk", Double(count) / 1000.0) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        return "\(count)"
    }
}
