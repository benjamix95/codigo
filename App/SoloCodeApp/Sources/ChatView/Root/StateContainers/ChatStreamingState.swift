import Foundation
import SwiftUI

// MARK: - ChatStreamingState

/// Groups all streaming, reasoning, and scroll-related @State properties
/// that were previously loose on ChatPanelView.
struct ChatStreamingState {

    // MARK: - Stream Throttle

    var pendingStreamContent: String?
    var pendingStreamConversationId: UUID?
    var streamThrottleTask: Task<Void, Never>?

    // MARK: - Plan Stream Throttle

    var pendingPlanStreamingContent: String?
    var pendingPlanStreamConversationId: UUID?
    var planStreamThrottleTask: Task<Void, Never>?

    // MARK: - Content Version

    var streamContentVersion: Int = 0

    // MARK: - Reasoning

    var streamingReasoningText: String?
    var streamingReasoningConversationId: UUID?
    var streamingReasoningBlocks: [ReasoningBlock] = []
    var streamingSegments: [MessageSegment] = []
    var streamingSegmentTurnIndex: Int = 0
    var codexLastReasoningLine: String?
    var reasoningMessageIdByConversationAndGroup: [UUID: [String: UUID]] = [:]

    // MARK: - Auto-Scroll

    var autoScrollWorkItem: DispatchWorkItem?
    var lastAutoScrollTarget: AnyHashable?
    var lastAutoScrollAt: Date = .distantPast
}
