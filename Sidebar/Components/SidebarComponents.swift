import SwiftUI

// MARK: - Empty State

struct SidebarEmptyState: View {
    let title: String
    let subtitle: String
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String,
        icon: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, DesignSystem.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }
}

// MARK: - Pinned Icon Button

struct SidebarPinnedIconButton: View {
    let onUnpin: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onUnpin) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering ? Color.white : DesignSystem.Colors.textSecondary.opacity(0.9))
        }
        .buttonStyle(.plain)
        .help("Unpin thread")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
