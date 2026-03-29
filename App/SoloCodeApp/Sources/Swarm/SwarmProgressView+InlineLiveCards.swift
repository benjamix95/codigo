import SwiftUI

extension SwarmProgressView {
    var inlineLiveCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("LIVE SUBAGENTS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer(minLength: 0)
                if let onSelectSwarm {
                    Button("Open panel") {
                        if let running = activeSwarmCards.first {
                            onSelectSwarm(running.swarmId)
                        } else if let first = finishedSwarmCards.first {
                            onSelectSwarm(first.swarmId)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(activeSwarmCards) { card in
                inlineLiveCard(card)
            }

            if !finishedSwarmCards.isEmpty {
                Divider().opacity(0.12).padding(.vertical, 2)

                HStack(spacing: 6) {
                    Text("FINISHED SUBAGENTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Spacer(minLength: 0)
                }

                ForEach(finishedSwarmCards) { card in
                    inlineLiveCard(card)
                }
            }
        }
    }

    func inlineLiveCard(_ card: SwarmLiveCardState) -> some View {
        let roleName = card.formattedTitle
        let subtitle = inlineCardSubtitle(for: card)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if card.status == .running {
                    SpinningDottedCircle()
                } else {
                    Image(systemName: inlineCardStatusIcon(for: card))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(card.status == .completed ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                        .frame(width: 14, alignment: .center)
                }

                Text(roleName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.74))
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.68))
                .lineLimit(1)
                .textShimmer(active: card.status == .running)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.18))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    func inlineCardSubtitle(for card: SwarmLiveCardState) -> String {
        if card.status == .running {
            return SubagentChatCardHelpers.runningSubtitle(
                detail: card.currentDetail,
                liveText: card.liveText
            )
        }
        if card.status == .completed {
            return card.warningCount > 0 ? "Done with warnings" : "Done"
        }
        if card.status == .failed {
            return "Failed"
        }
        return "Idle"
    }

    private func inlineCardStatusIcon(for card: SwarmLiveCardState) -> String {
        switch card.status {
        case .completed:
            return card.warningCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .running, .idle:
            return "circle"
        }
    }
}
