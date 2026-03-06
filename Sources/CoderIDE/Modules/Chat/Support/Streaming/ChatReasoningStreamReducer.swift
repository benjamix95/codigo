import Foundation

enum ChatReasoningPresentationMode {
    case inline
    case separateMessages
}

func shouldUpdateInlineReasoningState(
    eventConversationId: UUID?,
    selectedConversationId: UUID?
) -> Bool {
    guard let eventConversationId, let selectedConversationId else {
        return false
    }
    return eventConversationId == selectedConversationId
}

enum ChatReasoningPresentationPolicy {
    static func isCodexProvider(_ providerId: String) -> Bool {
        let normalized = providerId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.contains("codex")
    }

    static func mode(
        providerId: String,
        separateCodexThinkingMessagesEnabled: Bool
    ) -> ChatReasoningPresentationMode {
        guard separateCodexThinkingMessagesEnabled, isCodexProvider(providerId) else {
            return .inline
        }
        return .separateMessages
    }
}

struct ChatReasoningStreamReducer {
    struct State {
        var blocks: [ReasoningBlock]
        var text: String?
        var segments: [MessageSegment]
    }

    static func apply(
        output: String,
        groupId: String,
        state: State,
        sequentialStreamingLayoutEnabled: Bool,
        streamingSegmentTurnIndex: Int
    ) -> State {
        var nextState = state

        if let index = nextState.blocks.firstIndex(where: { $0.id == groupId }) {
            nextState.blocks[index].text = ChatPanelView.mergeReasoningText(
                existing: nextState.blocks[index].text,
                incoming: output
            )
        } else {
            nextState.blocks.append(ReasoningBlock(id: groupId, text: output))
        }

        nextState.text = nextState.blocks.map(\.text).joined(separator: "\n\n")

        guard sequentialStreamingLayoutEnabled else { return nextState }

        let segmentId = "reasoning-\(streamingSegmentTurnIndex)"
        let currentBlockText = nextState.blocks.last(where: { $0.id == groupId })?.text ?? output
        if let segmentIndex = nextState.segments.firstIndex(where: { $0.id == segmentId }) {
            nextState.segments[segmentIndex].kind = .reasoning(currentBlockText)
        } else {
            nextState.segments.append(
                MessageSegment(id: segmentId, kind: .reasoning(currentBlockText))
            )
        }

        return nextState
    }
}
