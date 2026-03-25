import AppKit
import SwiftUI

// MARK: - ChatTurnAction

/// Actions that ChatTurnView can dispatch to its parent.
/// Replaces 7 separate closure parameters, enabling Equatable
/// conformance on ChatTurnView (closures are not Equatable).
enum ChatTurnAction: Equatable {
    case fileClicked(String)
    case reviewChanges
    case openSubagentPanel(String)
    case stopSubagent
    case reply
    case edit
    case delete
}

// MARK: - ChatTurnView

struct ChatTurnView: View, Equatable {
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
    let todoItems: [TodoItem]
    let conversationId: UUID
    let shouldShowTodo: Bool
    let canEdit: Bool
    let canDelete: Bool
    let onAction: (ChatTurnAction) -> Void
    let showTopDivider: Bool

    nonisolated static func == (lhs: ChatTurnView, rhs: ChatTurnView) -> Bool {
        // Log which field caused the Equatable miss (re-render).
        let msgId = lhs.message.id.uuidString.prefix(8)
        if lhs.message.id != rhs.message.id {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] message.id changed")
            return false
        }
        if lhs.message.content != rhs.message.content {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] content changed (len \(lhs.message.content.count)→\(rhs.message.content.count))")
            return false
        }
        if lhs.message.isStreaming != rhs.message.isStreaming {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] isStreaming \(lhs.message.isStreaming)→\(rhs.message.isStreaming)")
            return false
        }
        if lhs.isActuallyLoading != rhs.isActuallyLoading {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] isActuallyLoading \(lhs.isActuallyLoading)→\(rhs.isActuallyLoading)")
            return false
        }
        if lhs.streamingStatusText != rhs.streamingStatusText {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] streamingStatusText changed")
            return false
        }
        if lhs.streamingDetailText != rhs.streamingDetailText {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] streamingDetailText changed")
            return false
        }
        if lhs.traceEvents.count != rhs.traceEvents.count {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] traceEvents.count \(lhs.traceEvents.count)→\(rhs.traceEvents.count)")
            return false
        }
        if lhs.inlineActivities.count != rhs.inlineActivities.count {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] inlineActivities.count \(lhs.inlineActivities.count)→\(rhs.inlineActivities.count)")
            return false
        }
        if lhs.liveSubagentCards.count != rhs.liveSubagentCards.count {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] liveSubagentCards.count \(lhs.liveSubagentCards.count)→\(rhs.liveSubagentCards.count)")
            return false
        }
        if lhs.todoItems.count != rhs.todoItems.count {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] todoItems.count \(lhs.todoItems.count)→\(rhs.todoItems.count)")
            return false
        }
        if lhs.conversationId != rhs.conversationId {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] conversationId changed")
            return false
        }
        if lhs.shouldShowTodo != rhs.shouldShowTodo {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] shouldShowTodo changed")
            return false
        }
        if lhs.canEdit != rhs.canEdit {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] canEdit changed")
            return false
        }
        if lhs.canDelete != rhs.canDelete {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] canDelete changed")
            return false
        }
        if lhs.showTopDivider != rhs.showTopDivider {
            ChatRenderLogger.logEquatableMiss("ChatTurnView", reason: "[\(msgId)] showTopDivider changed")
            return false
        }
        return true
    }

    @State private var didCopyMessage = false

    private var visibleBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.visibleBlocks(from: message.resolvedTimelineBlocks)
    }
    private var inlineTraceEvents: [ToolTraceEvent] {
        let filtered = traceEvents
            .filter { shouldShowInLinearChatOperationFeed($0, showTodoCard: shouldShowTodo && !todoItems.isEmpty) }
        // traceEvents from ToolTraceStore are already in insertion order
        // (NDJSON append-only). .filter() preserves relative order, so the
        // result is almost always already sorted. Check in O(n) before
        // paying O(n log n) for the sort — the common case during streaming
        // is that the array is already ordered.
        if filtered.count <= 1 { return filtered }
        var needsSort = false
        for i in 1..<filtered.count {
            let prev = filtered[i - 1]
            let curr = filtered[i]
            if prev.sequence > curr.sequence
                || (prev.sequence == curr.sequence && prev.timestamp > curr.timestamp) {
                needsSort = true
                break
            }
        }
        guard needsSort else { return filtered }
        return filtered.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
    }
    private var traceWorkspaceHints: [String] {
        context?.folderPaths.filter { !$0.isEmpty } ?? []
    }

    // MARK: - Interleaved Timeline Segments

    private var interleavedSegments: [ChatTurnInterleavedSegment] {
        let t0 = ChatRenderLogger.startTiming("interleave")
        let result = ChatTurnTimelineInterleaver.segments(
            blocks: visibleBlocks,
            traceEvents: inlineTraceEvents,
            liveSubagentCards: liveSubagentCards,
            subagentSnapshots: message.subagentCards ?? []
        )
        ChatRenderLogger.endTiming(
            "interleave(\(message.id.uuidString.prefix(8)))",
            start: t0,
            thresholdMs: 1.0
        )
        return result
    }

    var body: some View {
        let _ = ChatRenderLogger.startTiming("ChatTurnView.body")
        let _ = ChatRenderLogger.logRender(
            "ChatTurnView.body",
            detail: "msgId=\(message.id.uuidString.prefix(8)) streaming=\(message.isStreaming) loading=\(isActuallyLoading) traces=\(traceEvents.count) segments=\(interleavedSegments.count)"
        )
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
                onFileClicked: { onAction(.fileClicked($0)) },
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
                onOpenFile: { onAction(.fileClicked($0)) }
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .toolGroup(_, let group, _):
            InlineToolTraceGroupView(
                group: group,
                workspaceHints: traceWorkspaceHints,
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

            if canEdit {
                Button { onAction(.edit) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

            Button { onAction(.reply) } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)

            if canDelete {
                Button { onAction(.delete) } label: {
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

    nonisolated static func toolGroupCategory(for event: ToolTraceEvent) -> ChatTurnToolEventGroupCategory? {
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
