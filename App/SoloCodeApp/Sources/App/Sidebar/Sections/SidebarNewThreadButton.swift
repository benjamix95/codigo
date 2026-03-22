import SwiftUI

/// Single clean "New Thread" action button with keyboard shortcut hint.
struct SidebarNewThreadButton: View {
    let onNewThread: () -> Void

    var body: some View {
        Button(action: onNewThread) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text("New Thread")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\u{2318}N")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new thread")
    }
}
