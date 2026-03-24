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
    let supervisorActivities: [TaskActivity]
    let liveSubagentCards: [SwarmLiveCardState]
    @ObservedObject var todoStore: TodoStore
    let conversationId: UUID
    let shouldShowTodo: Bool
    let onFileClicked: (String) -> Void
    let onReviewChanges: () -> Void
    let onOpenSubagentPanel: (String) -> Void
    let onStopSubagent: () -> Void
    let onReply: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let showTopDivider: Bool

    @State private var didCopyMessage = false

    private var visibleBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.visibleBlocks(from: message.resolvedTimelineBlocks)
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

    // MARK: - Interleaved Timeline Segments

    private var interleavedSegments: [ChatTurnInterleavedSegment] {
        ChatTurnTimelineInterleaver.segments(
            blocks: visibleBlocks,
            traceEvents: inlineTraceEvents,
            liveSubagentCards: liveSubagentCards,
            subagentSnapshots: message.subagentCards ?? []
        )
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
            ForEach(interleavedSegments) { segment in
                segmentView(for: segment)
            }
            if message.isStreaming && isActuallyLoading {
                streamingFooter
            }
            actions
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    // MARK: - Segment Rendering

    @ViewBuilder
    private func segmentView(for segment: ChatTurnInterleavedSegment) -> some View {
        switch segment {
        case .text(_, let content, _):
            MarkdownContentView(
                content: content,
                context: context,
                onFileClicked: onFileClicked,
                textAlignment: .leading,
                isStreaming: message.isStreaming && isActuallyLoading
            )
            .frame(maxWidth: 800, alignment: .leading)
            .padding(.vertical, 4)

        case .reasoning(let id, let text, _):
            ThinkingBlocksView(
                blocks: [ReasoningBlock(id: id, text: text)],
                isLiveStreaming: message.isStreaming && isActuallyLoading
            )
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.vertical, 4)

        case .toolEvent(_, let event, _):
            InlineToolTraceEventView(
                event: event,
                workspaceHints: traceWorkspaceHints,
                onOpenFile: onFileClicked
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .toolGroup(_, let group, _):
            InlineToolTraceGroupView(
                group: group,
                workspaceHints: traceWorkspaceHints,
                onOpenFile: onFileClicked
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .subagentLiveCard(_, let card, _):
            SubagentChatCardView(
                card: card,
                onOpenInPanel: { onOpenSubagentPanel(card.swarmId) },
                onStop: onStopSubagent
            )
            .padding(.horizontal, 2)

        case .subagentSnapshot(_, let snapshot, _):
            SubagentSnapshotCardView(snapshot: snapshot)
                .padding(.horizontal, 2)

        case .artifact(_, let block, _):
            ArtifactCardView(
                block: block,
                accentColor: modeColor,
                context: context,
                onFileClicked: onFileClicked
            )
        }
    }

    // MARK: - Filter

    private func shouldShowInLinearChatOperationFeed(_ event: ToolTraceEvent, showTodoCard: Bool) -> Bool {
        shouldShowOperationEventInLinearChat(
            eventType: event.type,
            payload: event.payload,
            showTodoCard: showTodoCard
        )
    }

    // MARK: - Subviews

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

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

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

    // MARK: - Tool Group Categorization

    static func toolGroupCategory(for event: ToolTraceEvent) -> ChatTurnToolEventGroupCategory? {
        let type = event.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tool = MessageToolTraceToolIdentity.normalizedToolName(for: event)

        if type == "bash" || type == "command_execution" || tool == "bash" {
            return .terminal
        }
        if ToolTraceFileChangeMapper.isFileChangeEvent(event)
            || ["edit", "write", "str_replace", "regex_replace", "create_file", "delete_file"].contains(tool) {
            return .edit
        }
        if type.contains("read")
            || type.contains("search")
            || type.contains("grep")
            || type == "instant_grep"
            || ["read", "read_range", "batch_read", "glob", "list_dir", "find_files", "grep", "search", "semantic_search", "codebase_search", "find_symbol", "find_references", "file_outline"].contains(tool) {
            return .exploration
        }
        return nil
    }
}
