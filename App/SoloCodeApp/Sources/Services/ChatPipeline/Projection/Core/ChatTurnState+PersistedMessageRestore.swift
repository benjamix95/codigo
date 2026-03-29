import Foundation

func restoredChatTurnStateFromPersistedAssistantMessage(
    conversationId: UUID,
    message: ChatMessage,
    fallbackProviderId: String? = nil
) -> ChatTurnState {
    var state = ChatTurnState(
        conversationId: conversationId,
        assistantMessageId: message.id,
        turnId: message.turnMetadata?.turnId ?? message.id.uuidString,
        providerId: message.turnMetadata?.providerId ?? fallbackProviderId
    )
    state.status = message.turnMetadata?.status ?? "idle"
    state.isStreaming = message.isStreaming
    state.startedAt = message.turnMetadata?.startedAt
    state.completedAt = message.turnMetadata?.completedAt
    state.updatedAt = message.turnMetadata?.updatedAt
    state.sequence = message.turnMetadata?.sequence ?? 0
    state.orderedTextStreamIds = ["main"]

    let resolvedPrimaryText = message.resolvedPrimaryText
    if !resolvedPrimaryText.isEmpty {
        state.textByStreamId["main"] = resolvedPrimaryText
    }
    if let reasoning = message.reasoningText, !reasoning.isEmpty {
        state.reasoningByGroupId["reasoning"] = reasoning
    }

    let orderedBlocks = message.resolvedTimelineBlocks.sorted {
        if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
        return $0.id < $1.id
    }

    for block in orderedBlocks {
        switch block.kind {
        case .primaryText:
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let index = state.textSegments.count
            state.textSegments.append(block.text)
            state.timelineSegments.append(
                ChatTimelineSegment(kind: .text, index: index, sequence: block.sequence)
            )
        case .reasoning:
            guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            state.timelineSegments.append(
                ChatTimelineSegment(kind: .reasoning, index: 0, sequence: block.sequence)
            )
        case .toolMarker:
            state.timelineSegments.append(
                ChatTimelineSegment(kind: .toolUse, index: 0, sequence: block.sequence)
            )
        default:
            continue
        }
    }

    state.timelineNextSequence = (state.timelineSegments.map(\.sequence).max() ?? -1) + 1
    state.artifacts = message.resolvedTimelineBlocks.compactMap { block in
        persistedChatArtifact(from: block)
    }
    return state
}

private func persistedChatArtifact(from block: PersistedChatTimelineBlock) -> ChatArtifact? {
    switch block.kind {
    case .primaryText, .reasoning, .toolMarker:
        return nil
    case .mermaid:
        return ChatArtifact(id: block.id, kind: .mermaid, title: block.title ?? "Diagram", text: block.text)
    case .commands:
        return ChatArtifact(
            id: block.id,
            kind: .commands,
            title: block.title ?? "Commands executed",
            items: block.items,
            isCollapsedByDefault: true
        )
    case .files:
        return ChatArtifact(
            id: block.id,
            kind: .files,
            title: block.title ?? "Files touched",
            items: block.items,
            isCollapsedByDefault: true
        )
    case .status:
        return ChatArtifact(id: block.id, kind: .status, title: block.title ?? "Status", text: block.text)
    case .plan:
        return ChatArtifact(id: block.id, kind: .plan, title: block.title ?? "Plan", text: block.text)
    case .toolTrace:
        return ChatArtifact(
            id: block.id,
            kind: .toolTrace,
            title: block.title ?? "Trace summary",
            text: block.text,
            isCollapsedByDefault: true
        )
    }
}
