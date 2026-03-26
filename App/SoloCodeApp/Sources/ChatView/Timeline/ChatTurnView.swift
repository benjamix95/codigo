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

private struct ChatTurnLiveCardFingerprint: Equatable {
    let snapshot: SubagentCardSnapshot
    let isCollapsed: Bool
    let hasUnreadSinceCollapse: Bool

    init(card: SwarmLiveCardState) {
        self.snapshot = SubagentCardSnapshot(from: card)
        self.isCollapsed = card.isCollapsed
        self.hasUnreadSinceCollapse = card.hasUnreadSinceCollapse
    }
}

private struct ChatTurnSegmentView: View, Equatable {
    let segment: ChatTurnInterleavedSegment
    let context: ProjectContext?
    let modeColor: Color
    let isLiveStreaming: Bool
    let workspaceHints: [String]
    let onAction: (ChatTurnAction) -> Void

    static func == (lhs: ChatTurnSegmentView, rhs: ChatTurnSegmentView) -> Bool {
        guard lhs.isLiveStreaming == rhs.isLiveStreaming,
              lhs.workspaceHints == rhs.workspaceHints else { return false }

        let lhsContextKey = lhs.context.map { "\($0.id.uuidString.lowercased())|\($0.folderPaths.joined(separator: "|"))" }
        let rhsContextKey = rhs.context.map { "\($0.id.uuidString.lowercased())|\($0.folderPaths.joined(separator: "|"))" }
        guard lhsContextKey == rhsContextKey else { return false }

        switch (lhs.segment, rhs.segment) {
        case let (.text(lhsId, lhsContent, lhsSequence), .text(rhsId, rhsContent, rhsSequence)):
            return lhsId == rhsId && lhsContent == rhsContent && lhsSequence == rhsSequence

        case let (.reasoning(lhsId, lhsText, lhsSequence), .reasoning(rhsId, rhsText, rhsSequence)):
            return lhsId == rhsId && lhsText == rhsText && lhsSequence == rhsSequence

        case let (.toolEvent(lhsId, lhsEvent, lhsSequence), .toolEvent(rhsId, rhsEvent, rhsSequence)):
            return lhsId == rhsId && lhsEvent == rhsEvent && lhsSequence == rhsSequence

        case let (.toolGroup(lhsId, lhsGroup, lhsSequence), .toolGroup(rhsId, rhsGroup, rhsSequence)):
            return lhsId == rhsId && lhsGroup == rhsGroup && lhsSequence == rhsSequence

        case let (.subagentLiveCard(lhsId, lhsCard, lhsSequence), .subagentLiveCard(rhsId, rhsCard, rhsSequence)):
            return lhsId == rhsId
                && ChatTurnLiveCardFingerprint(card: lhsCard) == ChatTurnLiveCardFingerprint(card: rhsCard)
                && lhsSequence == rhsSequence

        case let (.subagentSnapshot(lhsId, lhsSnapshot, lhsSequence), .subagentSnapshot(rhsId, rhsSnapshot, rhsSequence)):
            return lhsId == rhsId && lhsSnapshot == rhsSnapshot && lhsSequence == rhsSequence

        case let (.artifact(lhsId, lhsBlock, lhsSequence), .artifact(rhsId, rhsBlock, rhsSequence)):
            return lhsId == rhsId && lhsBlock == rhsBlock && lhsSequence == rhsSequence

        default:
            return false
        }
    }

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
                workspaceHints: workspaceHints,
                onOpenFile: { onAction(.fileClicked($0)) }
            )
            .frame(maxWidth: 800, alignment: .leading)

        case .toolGroup(_, let group, _):
            InlineToolTraceGroupView(
                group: group,
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
    /// Provider effettivo del turno (es. da `resolvedTurnProviderId`); serve se `message.turnMetadata` non ha ancora `providerId`.
    let reasoningPolicyProviderId: String
    let shouldShowTodo: Bool
    let canEdit: Bool
    let canDelete: Bool
    let onAction: (ChatTurnAction) -> Void
    /// Tap su “Planning next move”: promuove todo o invia nudge se il thread è fermo.
    var onPlanningNextMoveTap: (() -> Void)? = nil
    let showTopDivider: Bool
    /// Se valorizzato (es. piano mostrato come placeholder in chat), la copia usa questo testo invece di `message.exportMarkdownContent`.
    var clipboardMarkdownOverride: String? = nil

    nonisolated static func == (lhs: ChatTurnView, rhs: ChatTurnView) -> Bool {
        if lhs.message.id != rhs.message.id { return false }
        if lhs.message.content != rhs.message.content { return false }
        if lhs.message.reasoningText != rhs.message.reasoningText { return false }
        if lhs.message.isStreaming != rhs.message.isStreaming { return false }
        if lhs.isActuallyLoading != rhs.isActuallyLoading { return false }
        if lhs.streamingStatusText != rhs.streamingStatusText { return false }
        if lhs.streamingDetailText != rhs.streamingDetailText { return false }
        if lhs.traceEvents.count != rhs.traceEvents.count { return false }
        if lhs.inlineActivities.count != rhs.inlineActivities.count { return false }
        if lhs.liveSubagentCards.count != rhs.liveSubagentCards.count { return false }
        if lhs.todoItems.count != rhs.todoItems.count { return false }
        if lhs.conversationId != rhs.conversationId { return false }
        if lhs.reasoningPolicyProviderId != rhs.reasoningPolicyProviderId { return false }
        if lhs.shouldShowTodo != rhs.shouldShowTodo { return false }
        if lhs.canEdit != rhs.canEdit { return false }
        if lhs.canDelete != rhs.canDelete { return false }
        if lhs.showTopDivider != rhs.showTopDivider { return false }
        if lhs.clipboardMarkdownOverride != rhs.clipboardMarkdownOverride { return false }
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
        let suppressReasoning = ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
            messageProviderId: message.turnMetadata?.providerId,
            fallbackTurnProviderId: reasoningPolicyProviderId
        )
        return ChatTurnTimelineInterleaver.segments(
            blocks: visibleBlocks,
            traceEvents: inlineTraceEvents,
            liveSubagentCards: liveSubagentCards,
            subagentSnapshots: message.subagentCards ?? [],
            suppressReasoningBlocks: suppressReasoning
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
                ChatTurnSegmentView(
                    segment: segment,
                    context: context,
                    modeColor: modeColor,
                    isLiveStreaming: message.isStreaming && isActuallyLoading,
                    workspaceHints: traceWorkspaceHints,
                    onAction: onAction
                )
            }
            if message.isStreaming && isActuallyLoading {
                streamingFooter
            }
            actions
        }
        .frame(maxWidth: 860, alignment: .leading)
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

    @ViewBuilder
    private var streamingFooter: some View {
        let status = streamingStatusText.isEmpty ? "Thinking" : streamingStatusText
        let reasoningSuppressed = ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
            messageProviderId: message.turnMetadata?.providerId,
            fallbackTurnProviderId: reasoningPolicyProviderId
        )
        let mutedPlanOrThink = status == "Thinking" || status == "Planning next move"
        let footerColor = mutedPlanOrThink
            ? DesignSystem.Colors.textTertiary
            : Color.secondary
        let showDetail = !reasoningSuppressed
            && status != "Thinking"
            && !(streamingDetailText?.isEmpty ?? true)
        let planningInteractive =
            status == "Planning next move"
            && message.isStreaming
            && isActuallyLoading
            && onPlanningNextMoveTap != nil

        let row = HStack(spacing: 6) {
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(footerColor)
                .textShimmer(active: true)
            if showDetail, let streamingDetailText, !streamingDetailText.isEmpty {
                Text("·")
                    .foregroundStyle(footerColor)
                Text(streamingDetailText)
                    .font(.system(size: 10))
                    .foregroundStyle(footerColor)
                    .lineLimit(1)
                    .textShimmer(active: true)
            }
            if planningInteractive {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(footerColor.opacity(0.9))
            }
            Spacer()
        }

        Group {
            if planningInteractive, let onTap = onPlanningNextMoveTap {
                Button(action: onTap) {
                    row
                }
                .buttonStyle(.plain)
                .help(
                    "Avvia il prossimo todo del piano o, se l’agente è fermo, invia un promemoria per proseguire."
                )
            } else {
                row
            }
        }
        .padding(.top, 2)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                let exportBody = clipboardMarkdownOverride ?? message.exportMarkdownContent
                NSPasteboard.general.setString(exportBody, forType: .string)
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
