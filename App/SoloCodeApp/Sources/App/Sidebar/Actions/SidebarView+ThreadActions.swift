import Foundation
import SwiftUI
import CoderEngine

// MARK: - Thread Deletion & Archive Actions

extension SidebarView {

    func cleanupConversationData(for conversation: Conversation) {
        NotificationCenter.default.post(
            name: ChatPanelView.threadDeletionRequestedNotification,
            object: nil,
            userInfo: ["conversationId": conversation.id.uuidString.lowercased()]
        )
        _ = pipelineIntegrationService.discardConversationRuntime(for: conversation.id)
        let roots = Set(conversation.checkpoints.flatMap { $0.gitStates.map(\.gitRootPath) })
        for root in roots {
            try? checkpointGitStore.deleteSnapshotBranch(conversationId: conversation.id, gitRoot: root)
        }
        projectContextStore.clearLastActiveConversation(conversationId: conversation.id)
        let purgeLegacyUnscopedAgent = chatStore.conversations.count <= 1
        todoStore.clearTodos(
            forConversationId: conversation.id,
            alsoRemoveLegacyUnscopedAgentRuntime: purgeLegacyUnscopedAgent
        )
    }

    func prepareConversationForArchive(_ conversation: Conversation) {
        guard chatStore.isTaskActive(for: conversation.id)
                || pipelineIntegrationService.isRunning(for: conversation.id)
        else { return }
        NotificationCenter.default.post(
            name: ChatPanelView.threadDeletionRequestedNotification,
            object: nil,
            userInfo: ["conversationId": conversation.id.uuidString.lowercased()]
        )
        _ = pipelineIntegrationService.discardConversationRuntime(for: conversation.id)
    }

    func deleteAllVisibleThreads() {
        let toDelete = visibleThreads
        guard !toDelete.isEmpty else { return }
        let fallbackContextId = activeContext?.id
        let fallbackFolderPath = scopedFolderPath(for: activeContext)
        var autoCreatedConversationId: UUID?
        for conv in toDelete {
            cleanupConversationData(for: conv)
            let outcome = chatStore.deleteConversation(id: conv.id)
            if let replacementId = outcome.autoCreatedReplacementId {
                autoCreatedConversationId = replacementId
            }
        }
        selectedConversationId = resolveAndApplySidebarThreadDeletionFallback(
            fallbackContextId: fallbackContextId,
            fallbackFolderPath: fallbackFolderPath,
            autoCreatedConversationId: autoCreatedConversationId
        )
    }

    func nextConversationAfterDelete(
        _ deleted: Conversation,
        autoCreatedId: UUID? = nil
    ) -> UUID? {
        if let replacement = visibleThreads.first(where: { $0.id != deleted.id }) {
            return replacement.id
        }
        return resolveAndApplySidebarThreadDeletionFallback(
            fallbackContextId: deleted.contextId,
            fallbackFolderPath: deleted.contextFolderPath,
            autoCreatedConversationId: autoCreatedId
        )
    }

    func nextConversationAfterArchive(_ archived: Conversation) -> UUID? {
        if let replacement = visibleThreads.first(where: { $0.id != archived.id }) {
            return replacement.id
        }
        return resolveAndApplySidebarThreadDeletionFallback(
            fallbackContextId: archived.contextId,
            fallbackFolderPath: archived.contextFolderPath,
            autoCreatedConversationId: nil
        )
    }
}
