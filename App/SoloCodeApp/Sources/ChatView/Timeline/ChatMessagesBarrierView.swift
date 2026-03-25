import SwiftUI

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

    let fingerprint: Fingerprint
    @ViewBuilder let content: () -> Content

    var body: some View {
        let _ = ChatRenderLogger.logRender(
            "MessagesBarrier.body",
            detail: "msgs=\(fingerprint.messageCount) loading=\(fingerprint.isLoading) traces=\(fingerprint.traceEventsTotalCount)"
        )
        content()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }

    struct Fingerprint: Equatable {
        let conversationId: UUID?
        let messageCount: Int
        let lastMessageId: UUID?
        let lastMessageContentLength: Int
        let lastMessageIsStreaming: Bool
        let lastMessageBlocksCount: Int
        let isLoading: Bool
        let traceEventsTotalCount: Int
    }
}
