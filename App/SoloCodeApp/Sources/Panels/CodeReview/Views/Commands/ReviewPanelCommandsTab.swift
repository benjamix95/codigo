import CoderEngine
import SwiftUI

/// Commands tab with mode selector, scope card, quick commands, workers, and live status.
struct ReviewPanelCommandsTab: View {
    @ObservedObject var store: CodeReviewPanelStore
    let onOpenFile: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                modeSelector
                scopeCard
                quickCommandsCard

                let m = store.computeMetrics()
                if !m.workers.isEmpty {
                    ReviewPanelWorkersCard(
                        workers: m.workers,
                        accent: store.accent,
                        onOpenFile: onOpenFile
                    )
                }
                if !m.cards.isEmpty {
                    liveStatusSection(m.cards)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text("REVIEW MODE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            HStack(spacing: 6) {
                Menu {
                    ForEach(ReviewScanDepth.allCases) { depth in
                        Button {
                            store.reviewScanDepth = depth
                        } label: {
                            HStack {
                                Text(depth.displayName)
                                if store.reviewScanDepth == depth {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 9, weight: .semibold))
                        Text(store.reviewScanDepth.displayName)
                            .font(.system(size: 9.5, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(store.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(store.accent.opacity(0.28), lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .help(store.reviewScanDepth.detail)

                HStack(spacing: 4) {
                    ForEach([CodeReviewPanelMode.securityAudit, .bugFinder]) { mode in
                        Button {
                            store.toggleModeSelection(mode)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 8))
                                Text(mode.displayName)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(
                                store.hasSelectedMode(mode)
                                    ? mode.accentColor : .secondary
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        store.hasSelectedMode(mode)
                                            ? mode.accentColor.opacity(0.14) : Color.primary.opacity(0.04)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        store.hasSelectedMode(mode)
                                            ? mode.accentColor.opacity(0.3)
                                            : DesignSystem.Colors.border.opacity(0.2),
                                        lineWidth: 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Scope Card

    private var scopeCard: some View {
        ReviewPanelScopeCard(store: store)
    }

    // MARK: - Quick Commands Card

    private var quickCommandsCard: some View {
        ReviewPanelQuickCommands(store: store)
    }

    // MARK: - Live Status

    private func liveStatusSection(_ cards: [SwarmLiveCardState]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text("LIVE STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(cards, id: \.swarmId) { card in
                liveStatusRow(card)
            }
        }
    }

    private func liveStatusRow(_ card: SwarmLiveCardState) -> some View {
        let cardAccent = statusAccent(card.status)
        let name = reviewCardDisplayName(card.swarmId)

        return HStack(spacing: 0) {
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
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: statusIcon(card))
                        .font(.system(size: 9))
                        .foregroundStyle(cardAccent.opacity(0.8))
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

    // MARK: - Helpers

    private func statusAccent(_ s: SwarmCardStatus) -> Color {
        switch s {
        case .running: return store.accent
        case .completed: return DesignSystem.Colors.success
        case .failed: return DesignSystem.Colors.error
        case .idle: return .secondary
        }
    }

    private func statusIcon(_ card: SwarmLiveCardState) -> String {
        if card.status == .failed { return "xmark.circle.fill" }
        if card.warningCount > 0 { return "exclamationmark.triangle.fill" }
        if card.status == .completed { return "checkmark.circle.fill" }
        return "circle"
    }

    private func reviewCardDisplayName(_ swarmId: String) -> String {
        let id = swarmId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.lowercased().hasPrefix("review-") {
            let suffix = String(id.dropFirst("review-".count))
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                return "Review \(suffix)"
            }
        }
        if let dash = id.range(of: "-", options: .backwards) {
            let suffix = id[dash.upperBound...]
            if suffix.count >= 8, suffix.allSatisfy(\.isHexDigit) {
                return String(id[..<dash.lowerBound]).capitalized
            }
        }
        return id.capitalized
    }
}
