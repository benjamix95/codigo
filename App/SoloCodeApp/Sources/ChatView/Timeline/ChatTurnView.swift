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

enum ChatTurnTimelineInterleaver {
    static func segments(
        blocks: [PersistedChatTimelineBlock],
        traceEvents: [ToolTraceEvent],
        liveSubagentCards: [SwarmLiveCardState] = [],
        subagentSnapshots: [SubagentCardSnapshot] = []
    ) -> [ChatTurnInterleavedSegment] {
        var segments: [ChatTurnInterleavedSegment] = []

        for block in blocks {
            switch block.kind {
            case .primaryText:
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(.text(id: block.id, content: block.text, sequence: block.sequence))
            case .reasoning:
                segments.append(.reasoning(id: block.id, text: block.text, sequence: block.sequence))
            case .toolMarker:
                // Placeholder only. Individual tool events are injected directly
                // from their own sequence numbers so the chat reads linearly.
                continue
            default:
                segments.append(.artifact(id: block.id, block: block, sequence: block.sequence))
            }
        }

        for event in traceEvents {
            segments.append(
                .toolEvent(
                    id: event.id.uuidString.lowercased(),
                    event: event,
                    sequence: event.sequence
                )
            )
        }

        let baseSequence = max(
            blocks.map(\.sequence).max() ?? 0,
            traceEvents.map(\.sequence).max() ?? 0
        )

        for (index, card) in liveSubagentCards.enumerated() {
            segments.append(
                .subagentLiveCard(
                    id: card.swarmId.lowercased(),
                    card: card,
                    sequence: sequenceForSubagentCard(
                        swarmId: card.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence,
                        offset: index
                    )
                )
            )
        }

        for (index, snapshot) in subagentSnapshots.enumerated() {
            segments.append(
                .subagentSnapshot(
                    id: snapshot.swarmId.lowercased(),
                    snapshot: snapshot,
                    sequence: sequenceForSubagentCard(
                        swarmId: snapshot.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence + liveSubagentCards.count,
                        offset: index
                    )
                )
            )
        }

        return segments.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.id < rhs.id
        }
    }

    private static func sequenceForSubagentCard(
        swarmId: String,
        traceEvents: [ToolTraceEvent],
        fallbackBase: Int,
        offset: Int
    ) -> Int {
        let normalizedSwarmId = swarmId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let earliestMatch = traceEvents
            .filter({
                ($0.payload["swarm_id"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == normalizedSwarmId
            })
            .map(\.sequence)
            .min() {
            return earliestMatch
        }
        return fallbackBase + offset + 1
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

                case .toolEvent(_, let event, _):
                    InlineToolTraceEventView(
                        event: event,
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

private struct InlineToolTraceEventView: View {
    let event: ToolTraceEvent
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    private var identity: MessageToolTraceToolIdentity {
        MessageToolTraceToolIdentity.resolve(for: event)
    }

    private var compactDetail: String? {
        let fileChange = ToolTraceFileChangeMapper.from(event: event)
        if let fileChange {
            let added = max(0, fileChange.added)
            let removed = max(0, fileChange.removed)
            if added > 0 || removed > 0 {
                return "+\(added) -\(removed)"
            }
            return fileChange.path ?? fileChange.basename
        }

        let candidates = [
            event.detail,
            event.payload["command"],
            event.payload["query"],
            event.payload["path"],
            event.payload["file"],
            event.payload["tool"],
            event.payload["mcp_tool"],
            event.payload["mcpTool"],
        ]

        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return String(text.prefix(140))
            }
        }
        return nil
    }

    private var openPath: String? {
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return FileChangePreviewResolver.resolveOpenPath(
                for: change,
                workspaceHints: workspaceHints
            )
        }
        let candidate = event.payload["path"] ?? event.payload["file"] ?? ""
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return candidate
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: identity.symbolName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(identity.tint)
                .frame(width: 14, alignment: .center)

            if let openPath {
                Button {
                    onOpenFile(openPath)
                } label: {
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textShimmer(active: event.isRunning)
                }
                .buttonStyle(.plain)
            } else {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .textShimmer(active: event.isRunning)
            }

            if let compactDetail, !compactDetail.isEmpty {
                Text(compactDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if event.isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if MessageToolTraceView.isErrorType(event) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else if MessageToolTraceView.isWarningType(event) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.18))
        )
    }
}
