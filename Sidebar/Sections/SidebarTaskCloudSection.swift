import SwiftUI
import CoderEngine

extension SidebarView {
    var taskCloudSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.7))

                Text("Task Cloud")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    loadCodexTasks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            if isLoadingTasks {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            } else if let first = codexTasks.first {
                Text(first.title ?? first.id)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
    }
}
