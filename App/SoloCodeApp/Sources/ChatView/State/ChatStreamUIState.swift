import Foundation
import SwiftUI

// MARK: - ChatStreamUIState

/// ObservableObject state container for streaming and rendering state.
/// Extracted from ChatPanelView to reduce @State explosion and isolate re-renders.
/// Uses ObservableObject (not @Observable) for macOS 13.0 compatibility.
@MainActor
final class ChatStreamUIState: ObservableObject {
    @Published var contentVersion: Int = 0
    @Published var activeTurnStateByConversation: [UUID: ChatTurnState] = [:]
    @Published var renderSnapshotByConversation: [UUID: ChatTurnState] = [:]
    @Published var collapsedArtifactsByTurn: [String: Set<String>] = [:]
    @Published var pipelineEventSequenceByConversation: [UUID: Int] = [:]
    @Published var reasoningText: String?
    @Published var reasoningConversationId: UUID?
    @Published var reasoningBlocks: [ReasoningBlock] = []
    @Published var segments: [MessageSegment] = []
    @Published var segmentTurnIndex: Int = 0
    @Published var reasoningMessageIdByConversationAndGroup: [UUID: [String: UUID]] = [:]
    @Published var codexLastReasoningLine: String?
    @Published var pendingContent: String?
    @Published var pendingConversationId: UUID?
    var throttleTask: Task<Void, Never>?
    @Published var isFollowingLive: Bool = true
    @Published var newEventsWhileDetached: Int = 0
    var autoScrollWorkItem: DispatchWorkItem?
    var lastAutoScrollTarget: AnyHashable?
    var lastAutoScrollAt: Date = .distantPast
    var fallbackTurnStartWorkItemsByConversation: [UUID: DispatchWorkItem] = [:]

    /// Resets streaming state for a clean slate.
    func reset() {
        reasoningText = nil
        reasoningConversationId = nil
        reasoningBlocks = []
        segments = []
        segmentTurnIndex = 0
        codexLastReasoningLine = nil
        pendingContent = nil
        pendingConversationId = nil
        throttleTask?.cancel()
        throttleTask = nil
    }
}
