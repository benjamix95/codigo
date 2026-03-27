import Foundation
import CoderEngine

struct MainChatRuntimeSnapshotBridge: Codable { var turnState: MainChatBridgeState; var mode: MainChatRuntimeModeBridge?; var directStream: MainChatDirectStreamSnapshotBridge?; var plan: MainChatPlanSnapshotBridge?; var output: MainChatRuntimeOutputBridge? }
enum MainChatRuntimeModeBridge: String, Codable { case agent, directStream, plan }
enum MainChatPlanPhaseBridge: String, Codable { case idle, analyzing, questioning, generating, proposalReady, readyToBuild, building }
enum MainChatPlanningStateKindBridge: String, Codable { case idle, awaitingClarification, awaitingChoice }
struct MainChatDirectStreamSnapshotBridge: Codable { var firstEventTimeoutSec: Int; var activityTimeoutSec: Int; var maxInitialRetries: Int; var maxStallRetries: Int; var initialRetryCount: Int; var stallRetryCount: Int; var hasReceivedAnyEvent: Bool; var emittedFirstText: Bool; var streamStartedAt: Date?; var lastEventAt: Date? }
struct MainChatPlanSnapshotBridge: Codable { var phase: MainChatPlanPhaseBridge?; var planningStateKind: MainChatPlanningStateKindBridge?; var clarificationQuestions: String?; var clarificationQuestionnaire: PlanClarificationQuestionnaire?; var proposalContent: String?; var summaryTitle: String?; var chosenPath: String?; var optionFullTexts: [String]; var optionTitles: [String]; var canonicalTodos: [String]; var userRequest: String; var analysisContext: String; var clarificationAnswers: String; var clarificationCycles: Int; var questionEpoch: Int; var shouldRunInline: Bool }
struct MainChatRuntimeOutputBridge: Codable { var chatContentOverride: String?; var shouldHidePlanMarkdown: Bool; var shouldOpenPlanPanel: Bool; var shouldFinalizeStream: Bool; var shouldRetryPoll: Bool; var followUpPrompt: String?; var generatedPrompt: String?; var terminalError: String?; var skipFullPlanPipeline: Bool? = nil }

private struct MainChatRuntimeActionBridgeRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let snapshot: MainChatRuntimeSnapshotBridge
    let timestamp: Date?
    let providerId: String?
    let status: String?
    let detail: String?
    let text: String?
    let questions: String?
    let planContent: String?
    let optionFullTexts: [String]
    let shouldRunInline: Bool?
    let isInitialPoll: Bool?
    let eventKind: String?
    let payload: [String: String]
}

private struct MainChatRuntimeActionBridgeResponse: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let runtimeSnapshot: MainChatRuntimeSnapshotBridge?
}

enum MainChatRuntimeUIEventKindBridge: String, Decodable {
    case started
    case textDelta
    case textReplace
    case raw
    case completed
    case error
}

enum MainChatRuntimeSignalKindBridge: String, Decodable {
    case firstEvent
    case firstTextDelta
    case streamCompleted
}

struct MainChatRuntimeUIEventBridge: Decodable {
    let kind: MainChatRuntimeUIEventKindBridge
    let text: String
    let rawType: String?
    let payload: [String: String]
}

struct MainChatRuntimeProviderPollBridgeRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let providerId: String
    let snapshot: MainChatRuntimeSnapshotBridge
    let timeoutMs: Int
}

struct MainChatRuntimeProviderPollBridgeResponse: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let runtimeSnapshot: MainChatRuntimeSnapshotBridge?
    var signals: [MainChatRuntimeSignalKindBridge] = []
    let uiEvents: [MainChatRuntimeUIEventBridge]
    let isTerminal: Bool
    let didTimeout: Bool
}

extension ConversationFlowCoordinator {
    func startDirectRuntime(
        providerId: String,
        turnId: String,
        timestamp: Date
    ) -> MainChatRuntimeSnapshotBridge? {
        callRuntimeAction(
            action: "direct_stream_start",
            snapshot: MainChatRuntimeSnapshotBridge(
                turnState: MainChatBridgeState(
                    conversationId: UUID(),
                    assistantMessageId: UUID(),
                    turnId: turnId,
                    providerId: providerId,
                    sequence: 0,
                    isStreaming: true,
                    startedAt: timestamp,
                    completedAt: nil,
                    updatedAt: timestamp,
                    status: "streaming",
                    orderedTextStreamIds: [],
                    textByStreamId: [:],
                    reasoningByGroupId: [:],
                    artifacts: [],
                    textSegments: [],
                    timelineSegments: [],
                    timelineNextSequence: 0
                ),
                mode: .directStream,
                directStream: MainChatDirectStreamSnapshotBridge(
                    firstEventTimeoutSec: initialEventTimeoutOverride ?? 90,
                    activityTimeoutSec: activityTimeoutOverride ?? 1800,
                    maxInitialRetries: initialRetryOverride ?? 4,
                    maxStallRetries: stallRetryOverride ?? 12,
                    initialRetryCount: 0,
                    stallRetryCount: 0,
                    hasReceivedAnyEvent: false,
                    emittedFirstText: false,
                    streamStartedAt: timestamp,
                    lastEventAt: timestamp
                ),
                plan: nil,
                output: nil
            ),
            timestamp: timestamp,
            providerId: providerId,
            status: "streaming"
        )
    }

    func finishDirectRuntime(
        status: String,
        detail: String?,
        wasCancelled: Bool,
        timestamp: Date
    ) -> MainChatRuntimeSnapshotBridge? {
        callRuntimeAction(
            action: wasCancelled ? "direct_stream_interrupt" : (status == "failed" ? "direct_stream_fail" : "direct_stream_complete"),
            snapshot: directRuntimeSnapshotState() ?? planRuntimeSnapshotState(),
            timestamp: timestamp,
            status: status,
            detail: detail
        )
    }

    func prepareDirectStreamContinuation(
        originalPrompt: String,
        currentText: String
    ) -> MainChatRuntimeSnapshotBridge? {
        callRuntimeAction(
            action: "direct_stream_prepare_continuation",
            snapshot: directRuntimeSnapshotState() ?? planRuntimeSnapshotState(),
            detail: originalPrompt,
            text: currentText
        )
    }

    func callRuntimeAction(
        action: String,
        snapshot: MainChatRuntimeSnapshotBridge?,
        timestamp: Date? = nil,
        providerId: String? = nil,
        status: String? = nil,
        detail: String? = nil,
        text: String? = nil,
        questions: String? = nil,
        planContent: String? = nil,
        optionFullTexts: [String] = [],
        shouldRunInline: Bool? = nil,
        isInitialPoll: Bool? = nil,
        eventKind: String? = nil,
        payload: [String: String] = [:]
    ) -> MainChatRuntimeSnapshotBridge? {
        guard let snapshot else { return nil }
        let response: MainChatRuntimeActionBridgeResponse? = ReviewCoreBridge.call(
            functionName: "chat_core_handle_action",
            request: MainChatRuntimeActionBridgeRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                timestamp: timestamp,
                providerId: providerId,
                status: status,
                detail: detail,
                text: text,
                questions: questions,
                planContent: planContent,
                optionFullTexts: optionFullTexts,
                shouldRunInline: shouldRunInline,
                isInitialPoll: isInitialPoll,
                eventKind: eventKind,
                payload: payload
            )
        )
        return response?.error == nil ? response?.runtimeSnapshot : nil
    }

}
