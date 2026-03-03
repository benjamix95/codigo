import SwiftUI

struct SubagentChatCardView: View {
    let card: SwarmLiveCardState
    let onOpenInPanel: () -> Void
    var onStop: (() -> Void)? = nil

    @State var isHovered = false
    @State var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            compactSnapshotSection
            expandedSnapshotSection
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isHovered || isExpanded ? 0.14 : 0.08),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: 480)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        }
    }
}
