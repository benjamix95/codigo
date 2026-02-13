import SwiftUI

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "checklist")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.primary.opacity(0.8))
                Text("Swarm \(store.steps.count)")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }

            ForEach(store.steps) { step in
                SwarmStepRow(step: step)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxHeight: 140)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium, tint: DesignSystem.Colors.swarmColor, borderOpacity: 0.08)
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct SwarmStepRow: View {
    let step: SwarmStep

    private var statusIcon: String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle"
        case .pending: return "circle"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.textTertiary
        case .inProgress: return DesignSystem.Colors.textSecondary
        case .pending: return DesignSystem.Colors.textTertiary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: statusIcon)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(statusColor)

            Text(step.name)
                .font(step.status == .inProgress ? DesignSystem.Typography.subheadlineMedium : DesignSystem.Typography.subheadline)
                .foregroundStyle(step.status == .completed ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                .strikethrough(step.status == .completed)
                .opacity(step.status == .completed ? 0.7 : 1)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
