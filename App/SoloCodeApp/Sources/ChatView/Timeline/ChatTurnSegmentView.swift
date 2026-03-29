import SwiftUI

struct ChatTurnSegmentView: View {
    let segment: ChatTurnInterleavedSegment
    let context: ProjectContext?
    let modeColor: Color
    let isLiveStreaming: Bool
    let messageIsStreaming: Bool
    let workspaceHints: [String]
    let onAction: (ChatTurnAction) -> Void

    var body: some View {
        switch segment {
        case .text(_, let content, _):
            MarkdownContentView(
                content: content,
                context: context,
                onFileClicked: { onAction(.fileClicked($0)) },
                textAlignment: .leading,
                isStreaming: isLiveStreaming
            )
            .frame(maxWidth: 800, alignment: .leading)
            .padding(.vertical, 4)

        case .reasoning(let id, let text, _):
            Group {
                ThinkingBlocksView(
                    blocks: [ReasoningBlock(id: id, text: text)],
                    isLiveStreaming: isLiveStreaming
                )
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.vertical, 4)
            }

        case .toolEvent(_, let event, _):
            InlineToolTraceEventView(
                event: event,
                messageIsStreaming: messageIsStreaming,
                workspaceHints: workspaceHints,
                onOpenFile: { onAction(.fileClicked($0)) }
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .toolGroup(_, let group, _):
            InlineToolTraceGroupView(
                group: group,
                messageIsStreaming: messageIsStreaming,
                workspaceHints: workspaceHints,
                onOpenFile: { onAction(.fileClicked($0)) }
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .subagentLiveCard(_, let card, _):
            SubagentChatCardView(
                card: card,
                onOpenInPanel: { onAction(.openSubagentPanel(card.swarmId)) },
                onStop: { onAction(.stopSubagent) }
            )
            .padding(.horizontal, 2)

        case .completedSubagentsGroup(_, let group, _):
            ChatTurnCompletedSubagentsGroupView(group: group)
                .padding(.horizontal, 2)

        case .subagentSnapshot(_, let snapshot, _):
            SubagentSnapshotCardView(snapshot: snapshot)
                .padding(.horizontal, 2)

        case .artifact(_, let block, _):
            ArtifactCardView(
                block: block,
                accentColor: modeColor,
                context: context,
                onFileClicked: { onAction(.fileClicked($0)) }
            )
        }
    }
}
