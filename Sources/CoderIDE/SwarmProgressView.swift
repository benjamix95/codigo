import SwiftUI

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore
    let activities: [TaskActivity]
    let isTaskRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.swarmColor)
                Text("SWARM · \(store.steps.count) steps")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 10).padding(.top, 6)

            ForEach(store.steps) { step in
                SwarmStepRow(step: step)
            }
            SwarmLiveBoardView(activities: activities, isTaskRunning: isTaskRunning)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .padding(.bottom, 8)
        .frame(maxHeight: 320)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
        }
    }
}

private struct SwarmStepRow: View {
    let step: SwarmStep

    private var statusIcon: String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle.fill"
        case .pending: return "circle"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.warning
        case .pending: return DesignSystem.Colors.borderAccent
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
            Text(step.name)
                .font(.system(size: 12, weight: step.status == .inProgress ? .medium : .regular))
                .foregroundStyle(step.status == .completed ? .tertiary : .primary)
                .strikethrough(step.status == .completed)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
    }
}
