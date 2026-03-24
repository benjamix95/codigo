import Foundation
import SwiftUI

// MARK: - ChatPanelView Stream State Aliases

/// Computed property aliases that forward to `streamState` (ChatStreamUIState).
/// These maintain backward compatibility with the extension files
/// that reference `self.streamContentVersion`, `self.isFollowingLive`, etc.
///
/// Once all extensions are migrated to use `streamState.xyz` directly,
/// these aliases can be removed.
extension ChatPanelView {
    var streamContentVersion: Int {
        get { streamState.contentVersion }
        nonmutating set { streamState.contentVersion = newValue }
    }

    var activeTurnStateByConversation: [UUID: ChatTurnState] {
        get { streamState.activeTurnStateByConversation }
        nonmutating set { streamState.activeTurnStateByConversation = newValue }
    }

    var renderSnapshotByConversation: [UUID: ChatTurnState] {
        get { streamState.renderSnapshotByConversation }
        nonmutating set { streamState.renderSnapshotByConversation = newValue }
    }

    var collapsedArtifactsByTurn: [String: Set<String>] {
        get { streamState.collapsedArtifactsByTurn }
        nonmutating set { streamState.collapsedArtifactsByTurn = newValue }
    }

    var pipelineEventSequenceByConversation: [UUID: Int] {
        get { streamState.pipelineEventSequenceByConversation }
        nonmutating set { streamState.pipelineEventSequenceByConversation = newValue }
    }

    var streamingReasoningText: String? {
        get { streamState.reasoningText }
        nonmutating set { streamState.reasoningText = newValue }
    }

    var streamingReasoningConversationId: UUID? {
        get { streamState.reasoningConversationId }
        nonmutating set { streamState.reasoningConversationId = newValue }
    }

    var streamingReasoningBlocks: [ReasoningBlock] {
        get { streamState.reasoningBlocks }
        nonmutating set { streamState.reasoningBlocks = newValue }
    }

    var streamingSegments: [MessageSegment] {
        get { streamState.segments }
        nonmutating set { streamState.segments = newValue }
    }

    var streamingSegmentTurnIndex: Int {
        get { streamState.segmentTurnIndex }
        nonmutating set { streamState.segmentTurnIndex = newValue }
    }

    var reasoningMessageIdByConversationAndGroup: [UUID: [String: UUID]] {
        get { streamState.reasoningMessageIdByConversationAndGroup }
        nonmutating set { streamState.reasoningMessageIdByConversationAndGroup = newValue }
    }

    var codexLastReasoningLine: String? {
        get { streamState.codexLastReasoningLine }
        nonmutating set { streamState.codexLastReasoningLine = newValue }
    }

    var pendingStreamContent: String? {
        get { streamState.pendingContent }
        nonmutating set { streamState.pendingContent = newValue }
    }

    var pendingStreamConversationId: UUID? {
        get { streamState.pendingConversationId }
        nonmutating set { streamState.pendingConversationId = newValue }
    }

    var streamThrottleTask: Task<Void, Never>? {
        get { streamState.throttleTask }
        nonmutating set { streamState.throttleTask = newValue }
    }

    var isFollowingLive: Bool {
        get { streamState.isFollowingLive }
        nonmutating set { streamState.isFollowingLive = newValue }
    }

    var newEventsWhileDetached: Int {
        get { streamState.newEventsWhileDetached }
        nonmutating set { streamState.newEventsWhileDetached = newValue }
    }

    var autoScrollWorkItem: DispatchWorkItem? {
        get { streamState.autoScrollWorkItem }
        nonmutating set { streamState.autoScrollWorkItem = newValue }
    }

    var lastAutoScrollTarget: AnyHashable? {
        get { streamState.lastAutoScrollTarget }
        nonmutating set { streamState.lastAutoScrollTarget = newValue }
    }

    var lastAutoScrollAt: Date {
        get { streamState.lastAutoScrollAt }
        nonmutating set { streamState.lastAutoScrollAt = newValue }
    }

    var fallbackTurnStartWorkItemsByConversation: [UUID: DispatchWorkItem] {
        get { streamState.fallbackTurnStartWorkItemsByConversation }
        nonmutating set { streamState.fallbackTurnStartWorkItemsByConversation = newValue }
    }
}
