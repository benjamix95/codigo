import AppKit
import SwiftUI

struct ChatTurnView: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    let traceEvents: [ToolTraceEvent]
    let inlineActivities: [TaskActivity]
    let liveSubagentCards: [SwarmLiveCardState]
    @ObservedObject var todoStore: TodoStore
    let conversationId: UUID
    let shouldShowTodo: Bool
    let onFileClicked: (String) -> Void
    let onReviewChanges: () -> Void
    let onOpenSubagentPanel: (String) -> Void
    let onStopSubagent: () -> Void
    let onReply: (() -> Void)?
    let onDelete: (() -> Void)?
    let showTopDivider: Bool

    @State private var didCopyMessage = false

    private var blocks: [PersistedChatTimelineBlock] { message.resolvedTimelineBlocks }
    private var visibleBlocks: [PersistedChatTimelineBlock] {
        blocks.filter { block in
            block.kind != .toolTrace
                && block.kind != .commands
                && block.kind != .files
                && block.kind != .status
        }
    }
    private var todoItems: [TodoItem] {
        todoStore.displayTodosForChat(for: conversationId)
    }
    private var inlineTraceEvents: [ToolTraceEvent] {
        traceEvents
            .filter { shouldShowInLinearChatOperationFeed($0, showTodoCard: shouldShowTodo && !todoItems.isEmpty) }
            .sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
    }
    private var traceWorkspaceHints: [String] {
        context?.folderPaths.filter { !$0.isEmpty } ?? []
    }
    private var shouldRenderInlineActivityFeed: Bool {
        message.isStreaming && isActuallyLoading && !inlineActivities.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showTopDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.bottom, 20)
            }
            header
            if let primary = visibleBlocks.first(where: { $0.kind == .primaryText }) {
                if !primary.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownContentView(
                        content: primary.text,
                        context: context,
                        onFileClicked: onFileClicked,
                        textAlignment: .leading,
                        isStreaming: message.isStreaming && isActuallyLoading
                    )
                    .frame(maxWidth: 800, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            if shouldRenderInlineActivityFeed {
                InlineActivityFeedView(
                    activities: inlineActivities,
                    modeColor: modeColor,
                    statusFromLLMOrActivity: streamingDetailText,
                    maxVisible: 24
                )
                .frame(maxWidth: 800, alignment: .leading)
            }
            if !shouldRenderInlineActivityFeed, !inlineTraceEvents.isEmpty {
                MessageToolTraceView(
                    events: inlineTraceEvents,
                    workspaceHints: traceWorkspaceHints,
                    onOpenFile: onFileClicked
                )
                .frame(maxWidth: 800, alignment: .leading)
            }
            if !liveSubagentCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(liveSubagentCards) { card in
                        SubagentChatCardView(
                            card: card,
                            onOpenInPanel: { onOpenSubagentPanel(card.swarmId) },
                            onStop: onStopSubagent
                        )
                    }
                }
                .padding(.horizontal, 2)
            } else if let snapshots = message.subagentCards, !snapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshots) { snapshot in
                        SubagentSnapshotCardView(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, 2)
            }
            if shouldShowTodo, !todoItems.isEmpty {
                TodoCenterCardView(
                    store: todoStore,
                    conversationId: conversationId,
                    traceEvents: traceEvents,
                    microStatusText: streamingDetailText,
                    isStreaming: message.isStreaming && isActuallyLoading,
                    onReviewChanges: onReviewChanges
                )
            }
            ForEach(visibleBlocks.filter { $0.kind != .primaryText }) { block in
                ArtifactCardView(
                    block: block,
                    accentColor: modeColor,
                    context: context,
                    onFileClicked: onFileClicked
                )
            }
            if message.isStreaming && isActuallyLoading {
                streamingFooter
            }
            actions
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private func shouldShowInLinearChatOperationFeed(_ event: ToolTraceEvent, showTodoCard: Bool) -> Bool {
        shouldShowOperationEventInLinearChat(
            eventType: event.type,
            payload: event.payload,
            showTodoCard: showTodoCard
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(modeColor.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
            Spacer(minLength: 0)
        }
    }

    private var streamingFooter: some View {
        HStack(spacing: 6) {
            Text(streamingStatusText.isEmpty ? "Thinking" : streamingStatusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textShimmer(active: true)
            if let streamingDetailText, !streamingDetailText.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(streamingDetailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textShimmer(active: true)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.exportMarkdownContent, forType: .string)
                didCopyMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    didCopyMessage = false
                }
            } label: {
                Image(systemName: didCopyMessage ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)

            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
