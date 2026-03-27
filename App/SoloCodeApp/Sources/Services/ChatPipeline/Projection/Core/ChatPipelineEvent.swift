import Foundation
import CoderEngine

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
        status: String? = nil,
        runtimeState: MainChatRuntimeBridgeState? = nil,
        data: [String: String] = [:]
    ) -> MainChatBridgeResponse? {
        ReviewCoreBridge.call(
            functionName: "chat_core_runtime_start",
            request: MainChatStartRequest(
                schemaVersion: 1,
                state: MainChatBridgeState(state),
                runtimeState: runtimeState,
                timestamp: timestamp,
                providerId: providerId,
                status: status,
                data: data
            )
        )
    }

    static func finish(
        state: ChatTurnState,
        timestamp: Date,
        status: String?,
        detail: String?,
        wasCancelled: Bool,
        runtimeState: MainChatRuntimeBridgeState? = nil
    ) -> MainChatBridgeResponse? {
        ReviewCoreBridge.call(
            functionName: "chat_core_runtime_finish",
            request: MainChatFinishRequest(
                schemaVersion: 1,
                state: MainChatBridgeState(state),
                runtimeState: runtimeState,
                timestamp: timestamp,
                status: status,
                detail: detail,
                wasCancelled: wasCancelled
            )
        )
    }

    static func handle(
        action: String,
        state: ChatTurnState,
        runtimeState: MainChatRuntimeBridgeState? = nil,
        timestamp: Date? = nil,
        status: String? = nil,
        detail: String? = nil,
        data: [String: String] = [:]
    ) -> MainChatBridgeResponse? {
        ReviewCoreBridge.call(
            functionName: "chat_core_handle_action",
            request: MainChatActionRequest(
                schemaVersion: 1,
                action: action,
                state: MainChatBridgeState(state),
                runtimeState: runtimeState,
                timestamp: timestamp,
                status: status,
                detail: detail,
                data: data
            )
        )
    }
}

enum MainChatRuntimeMode: String, Codable { case agent, directStream = "direct_stream", plan }
enum MainChatPlanPhase: String, Codable { case idle, analyzing, questioning, generating, proposalReady = "proposal_ready", readyToBuild = "ready_to_build", building }
enum MainChatPlanningStateKind: String, Codable { case idle, awaitingClarification = "awaiting_clarification", awaitingChoice = "awaiting_choice" }
enum MainChatSignalKind: String, Codable { case streamStarted = "stream_started", firstEvent = "first_event", firstTextDelta = "first_text_delta", streamCompleted = "stream_completed" }
struct MainChatRuntimeBridgeState: Codable, Equatable { var mode: MainChatRuntimeMode = .agent; var directStreamState: String?; var hasReceivedAnyEvent = false; var emittedFirstText = false; var firstEventTimeoutSec = 0; var activityTimeoutSec = 0; var maxInitialNoEventRetries = 0; var maxInactivityStallRetries = 0; var initialNoEventRetries = 0; var inactivityStallRetries = 0; var streamStartedAt: Date?; var lastEventAt: Date?; var autoContinuationRounds = 0; var maxAutoContinuationRounds = 0; var planPhase: MainChatPlanPhase = .idle; var planningStateKind: MainChatPlanningStateKind = .idle; var planUserRequest: String?; var planAnalysisContext: String?; var planClarificationQuestions: String?; var planClarificationAnswers: String?; var planContent: String?; var planClarificationCycles = 0; var shouldRunPlanInline = false }

struct MainChatBridgeState: Codable {
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
    let textSegments: [String]
    let timelineSegments: [ChatTimelineSegment]
    let timelineNextSequence: Int

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
        self.textSegments = state.textSegments
        self.timelineSegments = state.timelineSegments
        self.timelineNextSequence = state.timelineNextSequence
    }

    init(
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        providerId: String?,
        sequence: Int,
        isStreaming: Bool,
        startedAt: Date?,
        completedAt: Date?,
        updatedAt: Date?,
        status: String,
        orderedTextStreamIds: [String],
        textByStreamId: [String: String],
        reasoningByGroupId: [String: String],
        artifacts: [ChatArtifact],
        textSegments: [String] = [],
        timelineSegments: [ChatTimelineSegment] = [],
        timelineNextSequence: Int = 0
    ) {
        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.turnId = turnId
        self.providerId = providerId
        self.sequence = sequence
        self.isStreaming = isStreaming
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.status = status
        self.orderedTextStreamIds = orderedTextStreamIds
        self.textByStreamId = textByStreamId
        self.reasoningByGroupId = reasoningByGroupId
        self.artifacts = artifacts
        self.textSegments = textSegments
        self.timelineSegments = timelineSegments
        self.timelineNextSequence = timelineNextSequence
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
        state.textSegments = textSegments
        state.timelineSegments = timelineSegments
        state.timelineNextSequence = timelineNextSequence
        return state
    }
}

struct MainChatActionRequest: Encodable { let schemaVersion: Int; let action: String; let state: MainChatBridgeState; let runtimeState: MainChatRuntimeBridgeState?; let timestamp: Date?; let status: String?; let detail: String?; let data: [String: String] }
struct MainChatStartRequest: Encodable { let schemaVersion: Int; let state: MainChatBridgeState; let runtimeState: MainChatRuntimeBridgeState?; let timestamp: Date; let providerId: String?; let status: String?; let data: [String: String] }
struct MainChatReduceEventRequest: Encodable { let schemaVersion: Int; let state: MainChatBridgeState; let event: ChatPipelineEvent }
struct MainChatFinishRequest: Encodable { let schemaVersion: Int; let state: MainChatBridgeState; let runtimeState: MainChatRuntimeBridgeState?; let timestamp: Date; let status: String?; let detail: String?; let wasCancelled: Bool }
struct MainChatSignalBridgeEvent: Decodable, Equatable { let kind: MainChatSignalKind; let timestamp: Date }
struct MainChatBridgeResponse: Decodable { let schemaVersion: Int; let error: MainChatBridgeError?; let state: MainChatBridgeState?; let runtimeState: MainChatRuntimeBridgeState?; let prompt: String?; let chatContentOverride: String?; let nextPollTimeoutSeconds: Int?; let shouldHidePlanMarkdown: Bool?; let shouldOpenPlanPanel: Bool?; let shouldFinalizeStream: Bool?; let shouldRetryPoll: Bool?; let signals: [MainChatSignalBridgeEvent]? }
struct MainChatBridgeError: Decodable { let code: String; let message: String }
