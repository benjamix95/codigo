import SwiftUI

extension CodeReviewPanelView {
    // MARK: - Live Status Card

    func liveStatusCard(_ cards: [SwarmLiveCardState]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("LIVE STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(cards, id: \.swarmId) { card in
                let cardAccent = statusAccent(card.status)
                let name = reviewCardName(card.swarmId)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cardAccent)
                        .frame(width: 2.5)
                        .padding(.vertical, 3)

                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(card.currentStepTitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textShimmer(active: card.status == .running)

                        if card.warningCount > 0 && card.status != .failed {
                            Text("⚠︎ \(card.warningCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.warning)
                        }

                        Spacer(minLength: 4)

                        if card.status == .running {
                            ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: card.status == .failed
                                ? "xmark.circle.fill"
                                : (card.warningCount > 0 ? "exclamationmark.triangle.fill"
                                    : (card.status == .completed ? "checkmark.circle.fill" : "circle")))
                                .font(.system(size: 9))
                                .foregroundStyle((card.warningCount > 0 && card.status != .failed)
                                    ? DesignSystem.Colors.warning.opacity(0.85)
                                    : cardAccent.opacity(0.8))
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .padding(.trailing, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Bottom Bar

    var bottomBar: some View {
        HStack(spacing: 8) {
            if coderMode != .codeReviewMultiSwarm {
                Button {
                    onDispatchAction(.quickCommand(id: "review-uncommitted"))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 9))
                        Text("Start Review")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                    Text("Review mode active")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(accent)
            }

            Spacer()

            if coderMode == .codeReviewMultiSwarm && !isTaskRunning {
                Button {
                    if let sessionId = taskActivityStore.selectedCodeReviewSessionId(for: conversationId) {
                        onDispatchAction(.exportSummary(sessionId: sessionId))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 9))
                        Text("Export Summary")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Export the selected review summary")
            }

            if isTaskRunning && coderMode == .codeReviewMultiSwarm {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
