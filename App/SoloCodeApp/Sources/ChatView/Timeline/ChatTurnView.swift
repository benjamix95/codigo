import AppKit
import SwiftUI

enum ChatTurnTimelineOrdering {
    static func visibleBlocks(
        from blocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        blocks.filter { block in
            block.kind != .toolTrace
                && block.kind != .commands
                && block.kind != .files
                && block.kind != .status
        }
    }

    static func narrativeBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind == .reasoning }
    }

    static func detailBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind != .primaryText && $0.kind != .reasoning }
    }
}

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

    private var blocks: [PersistedChatTimelineBlock] { message.resolvedTimelineBlocks }
    private var visibleBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.visibleBlocks(from: blocks)
    }
    private var narrativeBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.narrativeBlocks(from: visibleBlocks)
    }
    private var detailBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.detailBlocks(from: visibleBlocks)
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

    /// Builds an interleaved timeline: text, reasoning, tool ops, artifacts
    /// sorted chronologically by sequence number.
    private var interleavedSegments: [ChatTurnInterleavedSegment] {
        var segments: [ChatTurnInterleavedSegment] = []

        // Collect toolMarker sequences so we can split tool trace events
        // into groups that align with the Rust-assigned timeline order.
        var toolMarkerSequences: [Int] = []

        // 1. Add visible blocks (text, reasoning, artifacts)
        for block in visibleBlocks {
            switch block.kind {
            case .primaryText:
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(.text(id: block.id, content: block.text, sequence: block.sequence))
            case .reasoning:
                segments.append(.reasoning(id: block.id, text: block.text, sequence: block.sequence))
            case .toolMarker:
                // Record marker sequence; the actual events are assigned below
                toolMarkerSequences.append(block.sequence)
            default:
                segments.append(.artifact(id: block.id, block: block, sequence: block.sequence))
            }
        }

        // 2. Assign tool trace events to marker slots.
        // If we have toolMarker blocks, distribute events across them
        // proportionally. Otherwise fall back to a single group.
        if !inlineTraceEvents.isEmpty {
            if toolMarkerSequences.isEmpty {
                // No markers — single group with sequence 0
                segments.append(.toolTrace(
                    id: "trace-\(message.id)",
                    events: inlineTraceEvents,
                    sequence: inlineTraceEvents.first?.sequence ?? 0
                ))
            } else {
                // Split events into groups by their sequence ranges.
                // Events with sequence <= first marker go to first marker,
                // events between marker N and marker N+1 go to marker N+1, etc.
                let sortedMarkers = toolMarkerSequences.sorted()
                var eventIndex = 0
                for (markerIdx, markerSeq) in sortedMarkers.enumerated() {
                    let nextMarkerSeq = markerIdx + 1 < sortedMarkers.count
                        ? sortedMarkers[markerIdx + 1]
                        : Int.max
                    var groupEvents: [ToolTraceEvent] = []
                    while eventIndex < inlineTraceEvents.count {
                        let evt = inlineTraceEvents[eventIndex]
                        if evt.sequence < nextMarkerSeq || markerIdx == sortedMarkers.count - 1 {
                            groupEvents.append(evt)
                            eventIndex += 1
                        } else {
                            break
                        }
                    }
                    if !groupEvents.isEmpty {
                        segments.append(.toolTrace(
                            id: "trace-\(message.id)-\(markerIdx)",
                            events: groupEvents,
                            sequence: markerSeq
                        ))
                    }
                }
                // Any remaining events
                if eventIndex < inlineTraceEvents.count {
                    let remaining = Array(inlineTraceEvents[eventIndex...])
                    let seq = sortedMarkers.last ?? 0
                    segments.append(.toolTrace(
                        id: "trace-\(message.id)-tail",
                        events: remaining,
                        sequence: seq + 1
                    ))
                }
            }
        }

        // 3. Sort by sequence
        return segments.sorted { $0.sequence < $1.sequence }
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
            // Interleaved timeline: text, reasoning, tool ops in chronological order
            ForEach(interleavedSegments) { segment in
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

                case .toolTrace(_, let events, _):
                    MessageToolTraceView(
                        events: events,
                        workspaceHints: traceWorkspaceHints,
                        onOpenFile: onFileClicked
                    )
                    .frame(maxWidth: 800, alignment: .leading)

                case .artifact(_, let block, _):
                    ArtifactCardView(
                        block: block,
                        accentColor: modeColor,
                        context: context,
                        onFileClicked: onFileClicked
                    )
                }
            }
            // Subagent cards (live or snapshot)
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
}
