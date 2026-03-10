import SwiftUI

/// Compact mode indicator badge for sidebar thread cards.
/// Shows the mode icon + short label in a colored capsule.
struct SidebarModeBadge: View {
    let mode: CoderMode

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            Image(systemName: mode.iconName)
                .font(.system(size: 8, weight: .semibold))
            Text(mode.shortLabel)
                .font(.system(size: 8, weight: .semibold))
        }
        .padding(.horizontal, DesignSystem.Spacing.xs + 1)
        .padding(.vertical, DesignSystem.Spacing.xxs)
        .foregroundStyle(mode.color)
        .background(mode.color.opacity(0.12), in: Capsule())
    }
}
