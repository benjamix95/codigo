import SwiftUI

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore
    let activities: [TaskActivity]
    let isTaskRunning: Bool
    let onSelectSwarm: ((String) -> Void)?
    private let inlineMaxWidth: CGFloat = 560

    private var swarmLanes: [SwarmLaneState] {
        TaskActivityStore.laneStates(from: activities)
            .filter { lane in
                !lane.swarmId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && lane.swarmId.lowercased() != "orchestrator"
            }
    }

    private var activeSubagentCount: Int {
        swarmLanes.filter { $0.status == .running }.count
    }

    private var stepCountLabel: String {
        let count = store.steps.count
        return count == 1 ? "1 step" : "\(count) steps"
    }

    private var activeAgentsLabel: String {
        let count = activeSubagentCount
        return count == 1 ? "1 active" : "\(count) active"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    swarmAntIcon
                    Text("SUBAGENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .textShimmer(active: isTaskRunning)
                }

                Spacer(minLength: 8)

                metricPill(
                    icon: "bolt.fill",
                    text: activeAgentsLabel,
                    tint: activeSubagentCount > 0 ? DesignSystem.Colors.swarmColor : .secondary,
                    isLive: isTaskRunning
                )
                metricPill(icon: "checklist", text: stepCountLabel, tint: .secondary)

                if isTaskRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignSystem.Colors.swarmColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if store.steps.isEmpty {
                Text("Waiting for subagent steps…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.steps) { step in
                        SwarmStepRow(step: step)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 1)
        }
        .overlay {
            if isTaskRunning {
                ActivityShimmerTrail()
                    .opacity(0.18)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.45))
                .frame(height: 0.5)
                .offset(y: 8)
        }
        // Keep the inline swarm strip centered in chat and prevent full-width expansion.
        .frame(maxWidth: inlineMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.leading, 6)
    }

    private var swarmAntIcon: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.swarmColor.opacity(0.18))
                .frame(width: 18, height: 18)
            Circle()
                .strokeBorder(DesignSystem.Colors.swarmColor.opacity(0.35), lineWidth: 0.8)
                .frame(width: 18, height: 18)
            Image(systemName: "ant.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.swarmColor,
                            DesignSystem.Colors.info.opacity(0.95),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func metricPill(icon: String, text: String, tint: Color, isLive: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .textShimmer(active: isLive)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
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

    private var statusLabel: String {
        switch step.status {
        case .completed: return "done"
        case .inProgress: return "running"
        case .pending: return "pending"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
            Text(step.name)
                .font(.system(size: 12, weight: step.status == .inProgress ? .medium : .regular))
                .foregroundStyle(step.status == .completed ? .tertiary : .primary)
                .strikethrough(step.status == .completed)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.8), lineWidth: 1)
        }
    }
}
