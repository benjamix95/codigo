import SwiftUI

/// Renders a sub-agent's transcript as a real chat using the same components
/// as the main chat: `MarkdownContentView` for text, `ThinkingBlockView`
/// for reasoning, `MessageToolTraceView` for tool operations.
/// Read-only — no composer.
struct SubagentChatView: View {
    let card: SwarmLiveCardState
    let isFollowingLive: Bool

    private var segments: [SubagentChatSegment] {
        SubagentChatSegmentBuilder.build(from: card)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        segmentView(segment)
                            .id(segment.id)
                    }

                    // Live status when waiting for first real content
                    if card.status == .running, segments.count <= 1 {
                        liveStatusIndicator
                    }

                    Color.clear.frame(height: 1).id("sa-chat-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: card.transcript.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: card.liveText.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: card.recentEvents.count) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    // MARK: - Segment Rendering

    @ViewBuilder
    private func segmentView(_ segment: SubagentChatSegment) -> some View {
        switch segment {
        case .taskPrompt(_, let text):
            taskPromptBubble(text: text)

        case .reasoning(_, let blocks, let isLive):
            ForEach(blocks) { block in
                ThinkingBlockView(
                    text: block.text,
                    isLiveStreaming: isLive && block.id == blocks.last?.id
                )
            }

        case .text(_, let content, let isStreaming):
            MarkdownContentView(
                content: content,
                context: nil,
                onFileClicked: { _ in },
                isStreaming: isStreaming
            )

        case .toolTrace(_, let events):
            MessageToolTraceView(
                events: events,
                workspaceHints: [],
                onOpenFile: { _ in }
            )

        case .result(_, let text, let timestamp):
            resultBubble(text: text, timestamp: timestamp)
        }
    }

    // MARK: - Live Status

    @ViewBuilder
    private var liveStatusIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(DesignSystem.Colors.swarmColor)
            Text(card.currentDetail.isEmpty ? card.currentStepTitle : card.currentDetail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.7))
                .lineLimit(2)
                .textShimmer(active: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Scroll

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("sa-chat-bottom", anchor: .bottom)
        }
    }
}
