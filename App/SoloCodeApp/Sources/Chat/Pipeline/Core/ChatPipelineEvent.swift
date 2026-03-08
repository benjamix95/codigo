import Foundation

enum ChatPipelineEventKind: String, Codable, Equatable {
    case turnStarted
    case turnCompleted
    case turnFailed
    case textDelta
    case textReplace
    case reasoningDelta
    case mermaidArtifact
    case toolTraceArtifact
    case commandsArtifact
    case filesArtifact
    case todoSnapshot
    case statusBadge
    case planArtifact
}

struct ChatPipelineEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let assistantMessageId: UUID
    let turnId: String
    let sequence: Int
    let source: String
    let kind: ChatPipelineEventKind
    let payload: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        sequence: Int,
        source: String,
        kind: ChatPipelineEventKind,
        payload: [String: String],
        timestamp: Date = .now
    ) {
        self.id = id
        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.turnId = turnId
        self.sequence = sequence
        self.source = source
        self.kind = kind
        self.payload = payload
        self.timestamp = timestamp
    }
}
