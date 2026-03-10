import SwiftUI

// MARK: - Sidebar Card

struct SidebarCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            content
        }
    }
}

// MARK: - Section Header

struct SidebarSectionHeader: View {
    let title: String
    var icon: String?
    var trailing: AnyView?

    init(_ title: String, icon: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
            trailing
        }
    }
}

// MARK: - Primary Action Button Style

struct SidebarPrimaryAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 5)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Sidebar Row

struct SidebarRow<Leading: View, Trailing: View>: View {
    let isActive: Bool
    let leading: Leading
    let trailing: Trailing

    init(isActive: Bool = false, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.isActive = isActive
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            leading
            Spacer(minLength: DesignSystem.Sidebar.insetXS)
            trailing
        }
        .padding(.horizontal, DesignSystem.Sidebar.insetXS)
        .padding(.vertical, DesignSystem.Sidebar.insetXS)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

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
