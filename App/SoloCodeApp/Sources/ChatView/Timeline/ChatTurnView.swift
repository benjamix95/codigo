import AppKit
import SwiftUI

// MARK: - ChatTurnAction

/// Actions that ChatTurnView can dispatch to its parent.
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

    @State private var didCopyMessage = false

    private var visibleBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.visibleBlocks(from: message.resolvedTimelineBlocks)
    }
    private var inlineTraceEvents: [ToolTraceEvent] {
        let filtered = traceEvents
            .filter { shouldShowInLinearChatOperationFeed($0) }
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
            suppressReasoningBlocks: suppressReasoning,
            debugAssistantMessageId: message.id,
            debugConversationId: conversationId
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    // #region agent log
                    let kinds = visibleBlocks.map(\.kind.rawValue).joined(separator: ",")
                    PlanFlowDebugNDJSONLog.append(
                        hypothesisId: "J",
                        location: "ChatTurnView.body.onAppear",
                        message: "chat_turn_visible_blocks",
                        data: [
                            "messageId": message.id.uuidString.lowercased(),
                            "conversationId": conversationId.uuidString.lowercased(),
                            "shouldShowTodo": shouldShowTodo ? "1" : "0",
                            "todoItemsCount": String(todoItems.count),
                            "visibleBlockCount": String(visibleBlocks.count),
                            "blockKinds": String(kinds.prefix(240)),
                            "isStreaming": message.isStreaming ? "1" : "0",
                        ]
                    )
                    if !traceEvents.isEmpty {
                        let todoLikeHidden = traceEvents.filter { ev in
                            let n = normalizedTodoPolicyToolName(type: ev.type, payload: ev.payload)
                            return n == "todo_read" || n == "todo_write"
                        }.count
                        Session989bc5DebugNDJSONLog.append(
                            hypothesisId: "H",
                            location: "ChatTurnView.body.onAppear",
                            message: "linear_chat_todo_trace_rows_normalized",
                            runId: "post-h2-fix",
                            data: [
                                "messageId": message.id.uuidString.lowercased(),
                                "traceTotal": String(traceEvents.count),
                                "inlineVisible": String(inlineTraceEvents.count),
                                "todoNormalizedRowsInTrace": String(todoLikeHidden),
                            ]
                        )
                    }
                    // #endregion
                }
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
                    messageIsStreaming: message.isStreaming,
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

    private func shouldShowInLinearChatOperationFeed(_ event: ToolTraceEvent) -> Bool {
        shouldShowOperationEventInLinearChat(
            eventType: event.type,
            payload: event.payload
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
        let showDetail = (
            reasoningSuppressed
                ? true
                : status != "Thinking"
        )
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
}
