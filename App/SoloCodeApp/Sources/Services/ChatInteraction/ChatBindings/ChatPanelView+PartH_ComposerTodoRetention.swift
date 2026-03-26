import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    private var composerTodoHasRecentNonEmptySnapshot: Bool {
        composerTodoLastNonEmptySnapshotAt > 0
            && (CFAbsoluteTimeGetCurrent() - composerTodoLastNonEmptySnapshotAt)
            < ChatPanelComposerTodoPolicy.retentionGraceIntervalSeconds
    }

    internal func composerTodoInputSignature(_ items: [TodoItem]) -> String {
        composerTodoAutoExpandSignature(items: items)
    }

    @MainActor
    private func scheduleComposerTodoGraceReevaluation() {
        composerTodoGraceTask?.cancel()
        let currentConversationId = conversationId
        let delayNs = UInt64(ChatPanelComposerTodoPolicy.retentionGraceIntervalSeconds * 1_000_000_000)
        composerTodoGraceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            guard composerTodoRetentionConversationId == currentConversationId else { return }
            let latestIncoming = composerTodoItems
            syncComposerTodoRetention(with: latestIncoming)
            composerTodoGraceTask = nil
        }
    }

    @MainActor
    internal func syncComposerTodoRetention(with incomingItems: [TodoItem]) {
        if composerTodoRetentionConversationId != conversationId {
            composerTodoGraceTask?.cancel()
            composerTodoGraceTask = nil
            composerRetainedTodoItems = []
            composerTodoLastNonEmptySnapshotAt = 0
            composerTodoRetentionConversationId = conversationId
        }

        let incomingHasOverlay = hasVisibleComposerTodoOverlay(items: incomingItems)
        if incomingHasOverlay {
            composerTodoGraceTask?.cancel()
            composerTodoGraceTask = nil
            composerRetainedTodoItems = incomingItems
            composerTodoLastNonEmptySnapshotAt = CFAbsoluteTimeGetCurrent()
            return
        }

        if shouldHoldComposerTodoOverlay(
            incomingItems: incomingItems,
            retainedItems: composerRetainedTodoItems,
            isLoading: isLoadingForCurrentConversation,
            isStreaming: composerTodoRetentionStreamingSignal,
            hasRecentNonEmptySnapshot: composerTodoHasRecentNonEmptySnapshot
        ) {
            scheduleComposerTodoGraceReevaluation()
            return
        }

        composerTodoGraceTask?.cancel()
        composerTodoGraceTask = nil
        composerRetainedTodoItems = []
        composerTodoLastNonEmptySnapshotAt = 0
    }

    internal func effectiveComposerTodoItems(from incomingItems: [TodoItem]) -> [TodoItem] {
        resolveEffectiveComposerTodoItems(
            incomingItems: incomingItems,
            retainedItems: composerRetainedTodoItems,
            isLoading: isLoadingForCurrentConversation,
            isStreaming: composerTodoRetentionStreamingSignal,
            hasRecentNonEmptySnapshot: composerTodoHasRecentNonEmptySnapshot
        )
    }

    @MainActor
    internal func syncComposerTodoOverlayExpansionState(with items: [TodoItem]) {
        let signature = composerTodoAutoExpandSignature(items: items)
        let hasOverlay = hasVisibleComposerTodoOverlay(items: items)

        guard hasOverlay else {
            composerTodoLastAutoExpandedSignature = ""
            composerTodoOverlayExpanded = false
            clearComposerTodoOverlayUserDismissedForSelection()
            return
        }

        guard signature != composerTodoLastAutoExpandedSignature else {
            if !composerTodoOverlayExpanded, let cid = conversationId {
                let userDismissedSig = composerTodoOverlayUserDismissedSignatureByConversation[cid]
                if userDismissedSig != signature {
                    composerTodoOverlayExpanded = true
                }
            }
            return
        }

        clearComposerTodoOverlayUserDismissedForSelection()
        composerTodoLastAutoExpandedSignature = signature
        composerTodoOverlayExpanded = true
    }
}
