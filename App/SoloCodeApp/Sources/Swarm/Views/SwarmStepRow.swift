import SwiftUI

struct SwarmStepRow: View {
    let step: SwarmStep
    let index: Int
    let showsConnector: Bool

    private var statusLabel: String {
        switch step.status {
        case .completed: return "done"
        case .inProgress: return "running"
        case .failed: return "failed"
        case .pending: return "pending"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.warning
        case .failed: return DesignSystem.Colors.error
        case .pending: return .secondary.opacity(0.7)
        }
    }

    private var badgeFillColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success.opacity(0.18)
        case .inProgress: return DesignSystem.Colors.warning.opacity(0.18)
        case .failed: return DesignSystem.Colors.error.opacity(0.18)
        case .pending: return Color.primary.opacity(0.06)
        }
    }

    private var badgeStrokeColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success.opacity(0.38)
        case .inProgress: return DesignSystem.Colors.warning.opacity(0.42)
        case .failed: return DesignSystem.Colors.error.opacity(0.42)
        case .pending: return DesignSystem.Colors.borderSubtle.opacity(0.95)
        }
    }

    private var rowFillColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success.opacity(0.08)
        case .inProgress: return DesignSystem.Colors.warning.opacity(0.09)
        case .failed: return DesignSystem.Colors.error.opacity(0.08)
        case .pending: return Color.primary.opacity(0.03)
        }
    }

    private var connectorColor: Color {
        switch step.status {
        case .completed:
            return DesignSystem.Colors.success.opacity(0.28)
        case .failed:
            return DesignSystem.Colors.error.opacity(0.28)
        default:
            return DesignSystem.Colors.borderSubtle.opacity(0.9)
        }
    }

    private var titleColor: Color {
        switch step.status {
        case .completed: return .secondary
        case .inProgress: return .primary
        case .failed: return DesignSystem.Colors.error
        case .pending: return .secondary.opacity(0.78)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(badgeFillColor)
                    Circle()
                        .strokeBorder(badgeStrokeColor, lineWidth: 1)

                    if step.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(statusColor)
                    } else if step.status == .inProgress {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(statusColor)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)

                if showsConnector {
                    Rectangle()
                        .fill(connectorColor)
                        .frame(width: 1.5, height: 22)
                        .padding(.top, 4)
                }
            }
            .frame(width: 20)

            HStack(alignment: .center, spacing: 8) {
                Text(step.name)
                    .font(.system(size: 12, weight: step.status == .inProgress ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .strikethrough(step.status == .completed)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowFillColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.78), lineWidth: 1)
            }
        }
    }
}
