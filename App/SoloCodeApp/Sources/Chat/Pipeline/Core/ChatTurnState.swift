import Foundation

struct ChatTurnMetadata: Codable, Equatable {
    var turnId: String
    var providerId: String?
    var sequence: Int
    var status: String
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date?
    var isStreaming: Bool
}

struct ChatTurnState: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let turnId: String
    var providerId: String?
    var sequence: Int
    var isStreaming: Bool
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date?
    var status: String
    var orderedTextStreamIds: [String]
    var textByStreamId: [String: String]
    var reasoningByGroupId: [String: String]
    var artifacts: [ChatArtifact]

    init(
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        providerId: String? = nil,
        status: String = "idle",
        orderedTextStreamIds: [String] = []
    ) {
        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.turnId = turnId
        self.providerId = providerId
        self.sequence = 0
        self.isStreaming = false
        self.startedAt = nil
        self.completedAt = nil
        self.updatedAt = nil
        self.status = status
        self.orderedTextStreamIds = orderedTextStreamIds
        self.textByStreamId = [:]
        self.reasoningByGroupId = [:]
        self.artifacts = []
    }

    var primaryTextSnapshot: String {
        orderedTextStreamIds
            .compactMap { textByStreamId[$0] }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var reasoningTextSnapshot: String? {
        let text = reasoningByGroupId
            .keys
            .sorted()
            .compactMap { reasoningByGroupId[$0] }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var blocks: [PersistedChatTimelineBlock] {
        var resolved: [PersistedChatTimelineBlock] = []
        resolved.append(
            PersistedChatTimelineBlock(
                id: "primary-text",
                kind: .primaryText,
                text: primaryTextSnapshot
            )
        )
        if let reasoning = reasoningTextSnapshot, !reasoning.isEmpty {
            resolved.append(
                PersistedChatTimelineBlock(
                    id: "reasoning",
                    kind: .reasoning,
                    title: "Thinking",
                    text: reasoning,
                    isCollapsible: true,
                    isCollapsedByDefault: true
                )
            )
        }
        resolved.append(contentsOf: artifacts.map(\.timelineBlock))
        return resolved
    }

    var metadata: ChatTurnMetadata {
        ChatTurnMetadata(
            turnId: turnId,
            providerId: providerId,
            sequence: sequence,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            updatedAt: updatedAt,
            isStreaming: isStreaming
        )
    }
}

private extension ChatArtifact {
    var timelineBlock: PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: id,
            kind: timelineKind,
            title: title,
            text: text,
            items: items,
            metadata: metadata,
            isCollapsible: isCollapsible,
            isCollapsedByDefault: isCollapsedByDefault
        )
    }

    var timelineKind: ChatTimelineBlockKind {
        switch kind {
        case .mermaid: return .mermaid
        case .commands: return .commands
        case .files: return .files
        case .status: return .status
        case .plan: return .plan
        case .toolTrace: return .toolTrace
        }
    }
}
