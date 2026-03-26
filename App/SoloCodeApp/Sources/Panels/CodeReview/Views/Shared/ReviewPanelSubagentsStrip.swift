import SwiftUI

/// Striscia compatta di subagent attivi per la review: chip orizzontali espandibili con transcript sotto.
struct ReviewPanelSubagentsStrip: View {
    @ObservedObject var store: CodeReviewPanelStore
    @State private var expandedSwarmId: String?

    private var cards: [SwarmLiveCardState] { store.reviewSubagentLiveCards }

    var body: some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cards) { card in
                                stripChip(
                                    card: card,
                                    isExpanded: expandedSwarmId == card.swarmId
                                ) {
                                    if expandedSwarmId == card.swarmId {
                                        expandedSwarmId = nil
                                    } else {
                                        expandedSwarmId = card.swarmId
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }

                    if let expandedId = expandedSwarmId,
                       let card = cards.first(where: { $0.swarmId == expandedId }) {
                        SubagentChatView(card: card, isFollowingLive: card.status == .running)
                            .frame(maxHeight: 240)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
            }
            .onChange(of: cards.map(\.swarmId)) { ids in
                if let id = expandedSwarmId, !ids.contains(id) {
                    expandedSwarmId = nil
                }
            }
        }
    }

    @ViewBuilder
    private func stripChip(
        card: SwarmLiveCardState,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                stripStatusIcon(for: card)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.formattedTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)

                    Text(stripSubtitle(for: card))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 156, maxWidth: 236, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isExpanded ? 0.22 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        store.accent.opacity(isExpanded ? 0.38 : 0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stripStatusIcon(for card: SwarmLiveCardState) -> some View {
        switch card.status {
        case .running:
            SpinningDottedCircle()
        case .completed:
            Image(systemName: card.warningCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(card.warningCount > 0 ? DesignSystem.Colors.warning : .green.opacity(0.75))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.75))
        case .idle:
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.35))
        }
    }

    private func stripSubtitle(for card: SwarmLiveCardState) -> String {
        if card.status == .running {
            let step = card.currentStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !step.isEmpty { return step }
            let detail = card.currentDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty { return detail }
            return "In corso…"
        }
        if card.status == .completed {
            if card.warningCount > 0 { return "Completato con avvisi" }
            if let s = card.summary, !s.isEmpty { return s }
            return "Completato"
        }
        if card.status == .failed { return "Errore" }
        return "In attesa"
    }
}
