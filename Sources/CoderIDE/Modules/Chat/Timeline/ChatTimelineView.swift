import SwiftUI

struct ChatTimelineView: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    let traceEvents: [ToolTraceEvent]
    let todoStore: TodoStore
    let conversationId: UUID
    let shouldShowTodo: Bool
    let onFileClicked: (String) -> Void
    let onRestoreCheckpoint: (() -> Void)?
    let onReply: (() -> Void)?
    let onDelete: (() -> Void)?
    let canRewind: Bool
    let hasCheckpointForRestore: Bool
    let showTopDivider: Bool

    var body: some View {
        if message.role == .user {
            MessageRow(
                message: message,
                context: context,
                modeColor: modeColor,
                isActuallyLoading: isActuallyLoading,
                streamingStatusText: streamingStatusText,
                streamingDetailText: streamingDetailText,
                onFileClicked: onFileClicked,
                onRestoreCheckpoint: onRestoreCheckpoint,
                onReply: onReply,
                onDelete: onDelete,
                canRewind: canRewind,
                hasCheckpointForRestore: hasCheckpointForRestore,
                showTopDivider: showTopDivider
            )
        } else {
            ChatTurnView(
                message: message,
                context: context,
                modeColor: modeColor,
                isActuallyLoading: isActuallyLoading,
                streamingStatusText: streamingStatusText,
                streamingDetailText: streamingDetailText,
                traceEvents: traceEvents,
                todoStore: todoStore,
                conversationId: conversationId,
                shouldShowTodo: shouldShowTodo,
                onFileClicked: onFileClicked,
                onReply: onReply,
                onDelete: onDelete,
                showTopDivider: showTopDivider
            )
        }
    }
}
