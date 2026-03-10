import SwiftUI

/// Flat inline action rows — no boxes, integrated into the sidebar flow.
struct SidebarNewThreadButton: View {
    let onNewThread: () -> Void
    let onOpenProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            Button(action: onNewThread) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "plus.message.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                    Text("New Thread")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new thread")

            Button(action: onOpenProject) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 16)
                    Text("Open Project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open project folder")
        }
    }
}
