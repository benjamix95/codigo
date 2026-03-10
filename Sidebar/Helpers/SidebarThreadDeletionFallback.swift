import Foundation

enum SidebarThreadDeletionFallback: Equatable {
    case selectExisting(UUID)
    case repurposeAutoCreatedEmptyThread(UUID)
    case createNew
}

extension SidebarView {
    @discardableResult
    func resolveAndApplySidebarThreadDeletionFallback(
        fallbackContextId: UUID?,
        fallbackFolderPath: String?,
        autoCreatedConversationId: UUID? = nil
    ) -> UUID? {
        let selectedConversationId: UUID?

        switch resolveSidebarThreadDeletionFallback(
            remainingConversations: chatStore.conversations,
            fallbackContextId: fallbackContextId,
            fallbackFolderPath: fallbackFolderPath,
            autoCreatedConversationId: autoCreatedConversationId
        ) {
        case .selectExisting(let conversationId):
            selectedConversationId = conversationId
        case .repurposeAutoCreatedEmptyThread(let conversationId):
            if fallbackContextId != nil || fallbackFolderPath != nil {
                chatStore.setContext(conversationId: conversationId, contextId: fallbackContextId)
                chatStore.setContextFolder(conversationId: conversationId, folderPath: fallbackFolderPath)
            }
            selectedConversationId = conversationId
        case .createNew:
            selectedConversationId = chatStore.createConversation(
                contextId: fallbackContextId,
                contextFolderPath: fallbackFolderPath
            )
        }

        if let fallbackContextId {
            projectContextStore.activeContextId = fallbackContextId
            syncActiveWorkspaceIfNeeded(contextId: fallbackContextId)
        }

        return selectedConversationId
    }
}

func resolveSidebarThreadDeletionFallback(
    remainingConversations: [Conversation],
    fallbackContextId: UUID?,
    fallbackFolderPath: String?,
    autoCreatedConversationId: UUID? = nil
) -> SidebarThreadDeletionFallback {
    if let sameContext = remainingConversations.first(where: {
        !$0.isArchived
            && $0.contextId == fallbackContextId
            && $0.contextFolderPath == fallbackFolderPath
    }) {
        return .selectExisting(sameContext.id)
    }

    if let autoCreatedConversationId,
       let autoCreatedConversation = remainingConversations.first(where: {
           $0.id == autoCreatedConversationId
       }),
       !autoCreatedConversation.isArchived,
       autoCreatedConversation.contextId == nil,
       autoCreatedConversation.contextFolderPath == nil,
       !autoCreatedConversation.messages.contains(where: { $0.role == .user }) {
        return .repurposeAutoCreatedEmptyThread(autoCreatedConversation.id)
    }

    return .createNew
}
