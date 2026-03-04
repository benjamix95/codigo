import SwiftUI

extension TaskActivityPanel {
    @ViewBuilder
    internal var swarmActivityContent: some View {
        if chatStore.isTaskActive(for: conversationId) {
            liveModeBanner
        }

        let cards = taskActivityStore.swarmCardStates(for: conversationId)
        let effectiveSwarmId = selectedSwarmLaneId ?? cards.first?.swarmId
        let selectedCard = cards.first(where: { $0.swarmId == effectiveSwarmId })
        let selectedLaneActivities = (selectedCard?.recentEvents ?? []).filter {
            TaskActivityStore.isConcreteVisibleEvent($0)
        }

        if let swarmId = effectiveSwarmId, !selectedLaneActivities.isEmpty {
            HStack {
                Text("Live details • Swarm \(swarmId)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 6)

            expandableSection(
                title: "Live activity",
                count: selectedLaneActivities.count,
                icon: "list.bullet.rectangle",
                color: .secondary,
                isExpanded: $isActivitiesExpanded
            ) {
                LiveActivityTimelineView(
                    activities: selectedLaneActivities,
                    maxVisible: 24,
                    workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                    onOpenFile: onOpenFile
                )
            }

            let swarmTerminals = selectedLaneActivities.filter {
                $0.type == "command_execution" || $0.type == "bash"
                    || ($0.type == "mcp_tool_call"
                        && ($0.payload["tool"] == "bash" || $0.payload["command"] != nil))
            }
            if !swarmTerminals.isEmpty {
                expandableSection(
                    title: "Terminals",
                    count: swarmTerminals.count,
                    icon: "terminal",
                    color: .secondary,
                    isExpanded: $isTerminalsExpanded
                ) {
                    ChatTerminalSessionsView(activities: selectedLaneActivities)
                }
            }

            WebSearchLiveView(activities: selectedLaneActivities)
        }
    }

    @ViewBuilder
    internal var liveModeBanner: some View {
        let isPaused = taskActivityStore.activities.last?.type == "process_paused"
        let phaseLabel: String = {
            if isPaused { return "Paused" }
            switch coderMode {
            case .plan: return "Plan"
            case .codeReviewMultiSwarm: return "Review"
            case .debug: return "Debug"
            default: return "Agent"
            }
        }()
        let text: String = {
            if isPaused {
                return "Execution paused"
            }
            switch coderMode {
            case .plan:
                let hasStepUpdate = taskActivityStore.activities.contains { $0.type == "plan_step_update" }
                let hasExecutionSignal = taskActivityStore.activities.contains {
                    $0.type == "command_execution" || $0.type == "file_change"
                }
                if hasExecutionSignal || hasStepUpdate {
                    return "Plan: executing plan"
                }
                return "Plan: analyzing options"
            case .codeReviewMultiSwarm:
                let hasFixRound = taskActivityStore.activities.contains { $0.type == "review-fix-round" }
                let hasWorkerPlan = taskActivityStore.activities.contains { $0.type == "review-worker-plan" }
                let hasExecutionSignal = taskActivityStore.activities.contains {
                    $0.type == "command_execution" || $0.type == "file_change"
                }
                if hasFixRound && hasExecutionSignal {
                    let roundInfo = taskActivityStore.activities.reversed().first { $0.type == "review-fix-round" }
                    let round = roundInfo?.payload["round"] ?? "?"
                    let maxRounds = roundInfo?.payload["maxRounds"] ?? "?"
                    return "Code Review: Fix Phase (Round \(round)/\(maxRounds))"
                }
                if hasWorkerPlan {
                    return "Code Review: Workers planned, starting fixes"
                }
                return "Code Review: Analyzing codebase"
            case .debug:
                if debugPhase.isActive {
                    return "Debug: \(debugPhase.label)"
                }
                return "Debug: investigating"
            default:
                return "Agent: task running"
            }
        }()
        let hint: String? = {
            guard !isPaused else { return "Press Resume to continue execution." }
            if coderMode == .codeReviewMultiSwarm {
                let hasWorkerPlan = taskActivityStore.activities.contains { $0.type == "review-worker-plan" }
                if !hasWorkerPlan {
                    return "Analyzing code for issues. Workers will be spawned automatically."
                }
            }
            if coderMode == .plan {
                let hasStepUpdate = taskActivityStore.activities.contains { $0.type == "plan_step_update" }
                if !hasStepUpdate {
                    return "When the plan is ready, choose an option to start the implementation."
                }
            }
            return nil
        }()
        let accent: Color = .secondary

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.error)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(phaseLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.4),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    @ViewBuilder
    internal func expandableSection<Content: View>(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.5)
        )
    }
}
