import SwiftUI
import CoderEngine

extension SidebarView {
    var taskCloudSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            SidebarSectionHeader("Task Cloud", icon: "cloud", trailing: AnyView(
                Button {
                    loadCodexTasks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            ))

            if isLoadingTasks {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            } else if let first = codexTasks.first {
                Text(first.title ?? first.id)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
    }
}
