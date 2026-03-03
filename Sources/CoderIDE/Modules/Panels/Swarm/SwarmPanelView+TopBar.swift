import SwiftUI

extension SwarmPanelView {
    // MARK: - Top Bar

    var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "ant.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text("Subagents")
                .font(.system(size: 13, weight: .semibold))

            if runningCount > 0 { badge("\(runningCount) running", accent) }
            if failedCount > 0 { badge("\(failedCount) failed", DesignSystem.Colors.error) }
            if warningCount > 0 { badge("\(warningCount) warnings", DesignSystem.Colors.warning) }
            if completedCount > 0 { badge("\(completedCount) done", DesignSystem.Colors.success) }

            Spacer()

            if isTaskRunning {
                ProgressView().controlSize(.mini)
            }

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Swarm Selector

    var swarmSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    selectorPill("Overview", icon: "square.grid.2x2", isSelected: selectedSwarmId == nil) {
                        withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = nil }
                    }
                    .id("sel-overview")

                    ForEach(sortedCards) { card in
                        selectorPill(
                            panelRoleDisplayName(from: card.swarmId),
                            isSelected: selectedSwarmId == card.swarmId
                        ) {
                            withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = card.swarmId }
                        }
                        .id("sel-\(card.swarmId)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedSwarmId) { _, newId in
                let target = newId.map { "sel-\($0)" } ?? "sel-overview"
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func selectorPill(
        _ title: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? accent : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Content

    @ViewBuilder
    var mainContent: some View {
        if sortedCards.isEmpty {
            emptyState
        } else if let sid = selectedSwarmId, let card = sortedCards.first(where: { $0.swarmId == sid }) {
            detailView(for: card)
        } else {
            overviewList
        }
    }

    // MARK: - Empty

    var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ant.fill")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No subagent activity")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Subagents will appear here when running")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

