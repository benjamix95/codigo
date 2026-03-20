import CoderEngine
import Foundation

@MainActor
enum ChatPipelineCommitter {
    static func commit(
        _ state: ChatTurnState,
        chatStore: ChatStore,
        persistImmediately: Bool
    ) {
        chatStore.updateAssistantMessagePipelineState(
            messageId: state.assistantMessageId,
            state: state,
            in: state.conversationId,
            persistImmediately: persistImmediately
        )
    }
}

enum MainChatRustBridge {
    static func reduce(
        state: ChatTurnState,
        event: ChatPipelineEvent
    ) -> ChatTurnState? {
        let response: MainChatBridgeResponse? = ReviewCoreBridge.call(
            functionName: "chat_core_runtime_reduce_event",
            request: MainChatReduceEventRequest(
                schemaVersion: 1,
                state: MainChatBridgeState(state),
                event: event
            )
        )
        guard response?.error == nil else { return nil }
        return response?.state?.chatTurnState
    }

    static func start(
        state: ChatTurnState,
        timestamp: Date,
        providerId: String?,
        status: String? = nil
    ) -> ChatTurnState? {
        let response: MainChatBridgeResponse? = ReviewCoreBridge.call(
            functionName: "chat_core_runtime_start",
            request: MainChatStartRequest(
                schemaVersion: 1,
                state: MainChatBridgeState(state),
                timestamp: timestamp,
                providerId: providerId,
                status: status
            )
        )
        guard response?.error == nil else { return nil }
        return response?.state?.chatTurnState
    }

    static func finish(
        state: ChatTurnState,
        timestamp: Date,
        status: String?,
        detail: String?,
        wasCancelled: Bool
    ) -> ChatTurnState? {
        let response: MainChatBridgeResponse? = ReviewCoreBridge.call(
            functionName: "chat_core_runtime_finish",
            request: MainChatFinishRequest(
                schemaVersion: 1,
                state: MainChatBridgeState(state),
                timestamp: timestamp,
                status: status,
                detail: detail,
                wasCancelled: wasCancelled
            )
        )
        guard response?.error == nil else { return nil }
        return response?.state?.chatTurnState
    }

    static func handle(
        action: String,
        state: ChatTurnState,
        timestamp: Date? = nil,
        status: String? = nil,
        detail: String? = nil
    ) -> ChatTurnState? {
        let response: MainChatBridgeResponse? = ReviewCoreBridge.call(
            functionName: "chat_core_handle_action",
            request: MainChatActionRequest(
                schemaVersion: 1,
                action: action,
                state: MainChatBridgeState(state),
                timestamp: timestamp,
                status: status,
                detail: detail
            )
        )
        guard response?.error == nil else { return nil }
        return response?.state?.chatTurnState
    }
}

private struct MainChatBridgeState: Codable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let turnId: String
    let providerId: String?
    let sequence: Int
    let isStreaming: Bool
    let startedAt: Date?
    let completedAt: Date?
    let updatedAt: Date?
    let status: String
    let orderedTextStreamIds: [String]
    let textByStreamId: [String: String]
    let reasoningByGroupId: [String: String]
    let artifacts: [ChatArtifact]

    init(_ state: ChatTurnState) {
        self.conversationId = state.conversationId
        self.assistantMessageId = state.assistantMessageId
        self.turnId = state.turnId
        self.providerId = state.providerId
        self.sequence = state.sequence
        self.isStreaming = state.isStreaming
        self.startedAt = state.startedAt
        self.completedAt = state.completedAt
        self.updatedAt = state.updatedAt
        self.status = state.status
        self.orderedTextStreamIds = state.orderedTextStreamIds
        self.textByStreamId = state.textByStreamId
        self.reasoningByGroupId = state.reasoningByGroupId
        self.artifacts = state.artifacts
    }

    var chatTurnState: ChatTurnState {
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId,
            status: status,
            orderedTextStreamIds: orderedTextStreamIds
        )
        state.sequence = sequence
        state.isStreaming = isStreaming
        state.startedAt = startedAt
        state.completedAt = completedAt
        state.updatedAt = updatedAt
        state.textByStreamId = textByStreamId
        state.reasoningByGroupId = reasoningByGroupId
        state.artifacts = artifacts
        return state
    }
}

private struct MainChatActionRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let state: MainChatBridgeState
    let timestamp: Date?
    let status: String?
    let detail: String?
}

private struct MainChatStartRequest: Encodable {
    let schemaVersion: Int
    let state: MainChatBridgeState
    let timestamp: Date
    let providerId: String?
    let status: String?
}

private struct MainChatReduceEventRequest: Encodable {
    let schemaVersion: Int
    let state: MainChatBridgeState
    let event: ChatPipelineEvent
}

private struct MainChatFinishRequest: Encodable {
    let schemaVersion: Int
    let state: MainChatBridgeState
    let timestamp: Date
    let status: String?
    let detail: String?
    let wasCancelled: Bool
}

private struct MainChatBridgeResponse: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let state: MainChatBridgeState?
}

private struct MainChatBridgeError: Decodable {
    let code: String
    let message: String
}
