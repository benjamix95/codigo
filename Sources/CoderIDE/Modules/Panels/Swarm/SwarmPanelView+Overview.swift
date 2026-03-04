import SwiftUI

extension SwarmPanelView {
    // MARK: - Overview List
    private var scopedSteps: [SwarmStep] {
        swarmProgressStore.steps(for: conversationId)
    }

    var overviewList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !scopedSteps.isEmpty {
                        progressSection
                    }
                    ForEach(sortedCards) { card in
                        overviewCard(card)
                            .id("ov-\(card.swarmId)")
                    }
                }
                .padding(12)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in isFollowingLive = false })
            .onChange(of: liveChangeCount) { _, _ in
                guard isFollowingLive,
                      let first = cachedCards.first(where: { $0.status == .running }) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("ov-\(first.swarmId)", anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress

    var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                Text("STEPS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }
            ForEach(scopedSteps) { step in
                HStack(spacing: 6) {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: 10))
                        .foregroundStyle(stepColor(step))
                    Text(step.name)
                        .font(.system(size: 11, weight: step.status == .inProgress ? .medium : .regular))
                        .foregroundStyle(step.status == .completed ? .tertiary : .primary)
                        .strikethrough(step.status == .completed)
                        .lineLimit(1)
                        .textShimmer(active: step.status == .inProgress)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        )
    }

    // MARK: - Overview Card (Minimal dark card)

    @ViewBuilder
    private func overviewCard(_ card: SwarmLiveCardState) -> some View {
        let roleName = panelRoleDisplayName(from: card.swarmId)

        let subtitle: String = {
            if card.status == .running {
                return liveSubtitle(for: card) ?? "Working..."
            }
            if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
            if card.status == .failed { return "Failed" }
            return "Idle"
        }()

        VStack(alignment: .leading, spacing: 4) {
            Text(roleName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineLimit(1)
                .textShimmer(active: card.status == .running)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = card.swarmId }
        }
    }
}
