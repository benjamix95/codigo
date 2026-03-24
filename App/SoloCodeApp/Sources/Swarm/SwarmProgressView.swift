import Foundation
import SwiftUI

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore
    @EnvironmentObject var pipelineService: PipelineIntegrationService
    let activities: [TaskActivity]
    let conversationId: UUID?
    let isTaskRunning: Bool
    let onSelectSwarm: ((String) -> Void)?
    private let inlineMaxWidth: CGFloat = 560
    @State private var showInlineLiveCards = false
    @State private var isExpanded = false

    private var scopedSteps: [SwarmStep] {
        store.steps(for: conversationId)
    }

    private var pipelineSnapshot: PipelineConversationSnapshot? {
        pipelineService.snapshot(for: conversationId)
    }

    private var isPipelineRunningForConversation: Bool {
        pipelineService.isRunning(for: conversationId)
    }

    private var progressMetrics: SwarmProgressMetrics {
        SwarmProgressMetrics(
            steps: scopedSteps,
            pipelineSnapshot: pipelineSnapshot
        )
    }

    var liveSwarmCards: [SwarmLiveCardState] {
        let reduced = SwarmLiveReducer.reduce(activities: activities, limitRecentEvents: 12)
        return SwarmLiveReducer.sorted(states: Array(reduced.values))
            .filter { card in
                !card.swarmId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && card.swarmId.lowercased() != "orchestrator"
            }
    }

    var body: some View {
        // Cache computed costosi una sola volta per render.
        let cards = liveSwarmCards
        let activeCount = cards.filter { $0.status == .running }.count
        let steps = scopedSteps
        let metrics = progressMetrics
        let pipelineRunning = isPipelineRunningForConversation
        let live = isTaskRunning || pipelineRunning
        let agentsLabel = activeCount == 1 ? "1 active" : "\(activeCount) active"

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    swarmAntIcon
                    Text(pipelineRunning ? "TASK" : "SUBAGENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .textShimmer(active: live)
                }

                Spacer(minLength: 8)

                Button {
                    guard !cards.isEmpty else { return }
                    withAnimation(.snappy(duration: 0.22)) {
                        showInlineLiveCards.toggle()
                    }
                } label: {
                    metricPill(
                        icon: "bolt.fill",
                        text: agentsLabel,
                        tint: activeCount > 0 ? DesignSystem.Colors.swarmColor : .secondary,
                        isLive: live,
                        accessorySymbol: cards.isEmpty ? nil : (showInlineLiveCards ? "chevron.up" : "chevron.down")
                    )
                }
                .buttonStyle(.plain)
                .help("Show/hide live subagent cards")
                .disabled(cards.isEmpty)

                if !metrics.isInternalSingleTaskPhase {
                    metricPill(
                        icon: "checklist",
                        text: metrics.progressLabel,
                        tint: metrics.progressedSteps > 0 ? DesignSystem.Colors.swarmColor : .secondary,
                        isLive: live
                    )
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse steps" : "Expand steps")

                if live {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignSystem.Colors.swarmColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if isExpanded {
                if metrics.totalSteps == 0 {
                    Text(pipelineRunning ? "Waiting for task steps…" : "Waiting for subagent steps…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                } else {
                    VStack(spacing: 6) {
                        SwarmProgressSummarySection(metrics: metrics)

                        if steps.isEmpty {
                            SwarmStepSyncPlaceholder()
                        } else {
                            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                SwarmStepRow(
                                    step: step,
                                    index: index,
                                    showsConnector: index < steps.count - 1
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }

            if showInlineLiveCards, !cards.isEmpty {
                inlineLiveCardsSection
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
            if live {
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
        .frame(maxWidth: inlineMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.leading, 6)
        .onChange(of: cards.count) { newValue in
            if newValue == 0 {
                showInlineLiveCards = false
            }
        }
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

    private func metricPill(
        icon: String,
        text: String,
        tint: Color,
        isLive: Bool = false,
        accessorySymbol: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .textShimmer(active: isLive)
            if let accessorySymbol {
                Image(systemName: accessorySymbol)
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
