import SwiftUI

struct ChatTurnCompletedSubagentsGroupView: View {
    let group: ChatTurnCompletedSubagentsGroup

    @State private var expansionState: ChatTurnCompletedSubagentsGroupExpansionState

    init(group: ChatTurnCompletedSubagentsGroup) {
        self.group = group
        _expansionState = State(
            initialValue: ChatTurnCompletedSubagentsGroupExpansionState.initial(
                hasCards: !group.cards.isEmpty
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
                    Image(systemName: "person.2.crop.square.stack.fill")
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

                    ForEach(group.cards) { snapshot in
                        SubagentSnapshotCardView(snapshot: snapshot)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}
