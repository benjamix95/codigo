import SwiftUI

struct ChatTurnCompletedSubagentsGroupView: View {
    let group: ChatTurnCompletedSubagentsGroup
    let onOpenSubagentPanel: (String) -> Void
    let onStopSubagent: () -> Void

    @State private var expansionState: ChatTurnCompletedSubagentsGroupExpansionState

    init(
        group: ChatTurnCompletedSubagentsGroup,
        onOpenSubagentPanel: @escaping (String) -> Void,
        onStopSubagent: @escaping () -> Void
    ) {
        self.group = group
        self.onOpenSubagentPanel = onOpenSubagentPanel
        self.onStopSubagent = onStopSubagent
        _expansionState = State(
            initialValue: ChatTurnCompletedSubagentsGroupExpansionState.initial(
                hasEntries: !group.entries.isEmpty,
                hasRunningEntries: group.hasRunningEntries
            )
        )
    }

    private var presentation: ChatTurnCompletedSubagentsGroupPresentation {
        ChatTurnCompletedSubagentsGroupPresentation.make(group: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    expansionState.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.info)

                    Text(presentation.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text(presentation.badgeText)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignSystem.Colors.backgroundTertiary.opacity(0.9))
                        )

                    Image(systemName: expansionState.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.75), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            if expansionState.isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.leading, 2)

                    ForEach(group.entries) { entry in
                        if entry.isRunning, let liveCard = entry.liveCard {
                            SubagentChatCardView(
                                card: liveCard,
                                onOpenInPanel: { onOpenSubagentPanel(liveCard.swarmId) },
                                onStop: onStopSubagent
                            )
                        } else {
                            SubagentSnapshotCardView(snapshot: entry.snapshot)
                        }
                    }
                }
                .padding(.leading, 2)
            }
        }
        .onAppear(perform: syncExpansionState)
        .onChange(of: lifecycleToken) { _ in
            syncExpansionState()
        }
    }

    private var lifecycleToken: String {
        group.entries.map {
            "\($0.id):\($0.status.rawValue)"
        }.joined(separator: "|")
    }

    private func syncExpansionState() {
        let next = ChatTurnCompletedSubagentsGroupPresentation.reconcile(
            current: expansionState,
            hasEntries: !group.entries.isEmpty,
            hasRunningEntries: group.hasRunningEntries
        )
        guard next != expansionState else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            expansionState = next
        }
    }
}
