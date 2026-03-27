import SwiftUI

struct ChatMessagesBarrierFingerprint: Equatable {
    let conversationId: UUID?
    let messageCount: Int
    let lastMessageId: UUID?
    let lastMessageContentLength: Int
    let lastMessageReasoningLength: Int
    let lastMessageIsStreaming: Bool
    let lastMessageBlocksCount: Int
    let lastMessageTraceEventsCount: Int
    let isLoading: Bool
}

func buildChatMessagesBarrierFingerprint(
    conversationId: UUID?,
    messages: [ChatMessage],
    traceEventsByMessageId: [UUID: [ToolTraceEvent]],
    isLoading: Bool
) -> ChatMessagesBarrierFingerprint {
    let lastMessage = messages.last
    return .init(
        conversationId: conversationId,
        messageCount: messages.count,
        lastMessageId: lastMessage?.id,
        lastMessageContentLength: lastMessage?.content.count ?? 0,
        lastMessageReasoningLength: lastMessage?.reasoningText?.count ?? 0,
        lastMessageIsStreaming: lastMessage?.isStreaming ?? false,
        lastMessageBlocksCount: lastMessage?.blocks?.count ?? 0,
        lastMessageTraceEventsCount: lastMessage.flatMap { traceEventsByMessageId[$0.id]?.count } ?? 0,
        isLoading: isLoading
    )
}

/// Equatable barrier that prevents parent body invalidations from
/// cascading into the messages list. SwiftUI compares the `Fingerprint`
/// before re-evaluating the content closure. If the fingerprint hasn't
/// changed, the expensive `messagesStack` body is skipped entirely.
///
/// This is necessary because `ChatPanelView` has 14+ EnvironmentObjects.
/// Any change to any of them triggers a parent body re-evaluation that
/// would otherwise cascade through `rootLayout` → `messagesArea` →
/// `messagesAreaScrollView` → `chatMessagesAreaContent` → `messagesStack`.
struct ChatMessagesBarrierView<Content: View>: View, Equatable {

    let fingerprint: ChatMessagesBarrierFingerprint
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }
}
