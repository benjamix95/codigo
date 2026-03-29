import Foundation
import SwiftUI

// MARK: - ChatStreamingState

/// Groups streaming, reasoning, and content-version @State properties.
/// Auto-scroll state was extracted into `ChatScrollState` (below)
/// because it changes on every scroll event during streaming, and
/// bundling it here caused the entire struct to be re-observed on
/// every scroll — invalidating views that only care about content.
struct ChatStreamingState {

    // MARK: - Stream Throttle

    var pendingStreamContent: String?
    var pendingStreamConversationId: UUID?
    var pendingStreamQueuedAt: Date?
    var pendingStreamOverwriteCount: Int = 0
    var streamThrottleTask: Task<Void, Never>?

    // MARK: - Plan Stream Throttle

    var pendingPlanStreamingContent: String?
    var pendingPlanStreamConversationId: UUID?
    var planStreamThrottleTask: Task<Void, Never>?

    // MARK: - Content Version

    var streamContentVersion: Int = 0
    var lastMainChatStreamApplyAt: Date?
    var lastMainChatStreamApplyLen: Int = 0

    // MARK: - Reasoning

    var streamingReasoningText: String?
    var streamingReasoningConversationId: UUID?
    var streamingReasoningBlocks: [ReasoningBlock] = []
    var streamingSegments: [MessageSegment] = []
    var streamingSegmentTurnIndex: Int = 0
    var codexLastReasoningLine: String?
    var reasoningMessageIdByConversationAndGroup: [UUID: [String: UUID]] = [:]
}

// MARK: - ChatScrollState

/// Auto-scroll state extracted from ChatStreamingState.
/// These 3 fields change on every `scheduleAutoScroll` call during
/// streaming. Keeping them in a separate @State prevents scroll
/// updates from invalidating views that observe streaming content
/// or reasoning state.
struct ChatScrollState {
    var autoScrollWorkItem: DispatchWorkItem?
    var lastAutoScrollTarget: AnyHashable?
    var lastAutoScrollAt: Date = .distantPast
    var lastProgrammaticScrollAt: Date = .distantPast
    var pendingProgrammaticViewportObservations = 0
}
