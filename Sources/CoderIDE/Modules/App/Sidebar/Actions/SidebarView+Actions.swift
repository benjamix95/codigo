import Foundation
import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    func askAIAboutThreadSearch(query: String, hits: [ThreadSearchHit]) {
        let prompt = chatStore.buildThreadSearchAIPrompt(query: query, hits: hits)
        NotificationCenter.default.post(
            name: Notification.Name("CoderIDE.ThreadSearchAskAI"),
            object: nil,
            userInfo: ["prompt": prompt]
        )
    }

    func cleanupConversationData(for conversation: Conversation) {
        let roots = Set(conversation.checkpoints.flatMap { $0.gitStates.map(\.gitRootPath) })
        for root in roots {
            try? checkpointGitStore.deleteSnapshotBranch(conversationId: conversation.id, gitRoot: root)
        }
        projectContextStore.clearLastActiveConversation(conversationId: conversation.id)
    }

    func deleteAllVisibleThreads() {
        let toDelete = visibleThreads
        let deletedIds = Set(toDelete.map(\.id))
        let wasSelectingOne = deletedIds.contains(selectedConversationId ?? UUID())
        for conv in toDelete {
            cleanupConversationData(for: conv)
            chatStore.deleteConversation(id: conv.id)
        }
        if wasSelectingOne {
            // Pick the best remaining thread in the same context, not just any thread.
            let contextId = currentContext?.id
            selectedConversationId = chatStore.conversations.first(where: {
                !$0.isArchived && $0.contextId == contextId && !deletedIds.contains($0.id)
            })?.id ?? chatStore.conversations.first(where: { !deletedIds.contains($0.id) })?.id
        }
    }

    func nextConversationSelectionAfterDelete(deletedConversation: Conversation) -> UUID? {
        // Keep focus in the same context/folder when possible.
        if let replacement = visibleThreads.first(where: { $0.id != deletedConversation.id }) {
            return replacement.id
        }

        // Fallback: most recent non-archived thread in the same context.
        if let sameContext = chatStore.conversations.first(where: {
            !$0.isArchived
                && $0.id != deletedConversation.id
                && $0.contextId == deletedConversation.contextId
                && $0.contextFolderPath == deletedConversation.contextFolderPath
        }) {
            return sameContext.id
        }

        // Last fallback: first available thread.
        return chatStore.conversations.first?.id
    }

    func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        syncActiveWorkspaceIfNeeded(contextId: contextId)
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil
        // If there's a thread you worked on in this tab, show it; otherwise new thread
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived,
           lastConv.messages.contains(where: { $0.role == .user }) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
    }

    func syncActiveWorkspaceIfNeeded(contextId: UUID?) {
        guard let contextId else { return }
        let newId: UUID? = workspaceStore.workspaces.contains(where: { $0.id == contextId }) ? contextId : nil
        guard workspaceStore.activeWorkspaceId != newId else { return }
        workspaceStore.activeWorkspaceId = newId
        workspaceStore.save()
    }

    func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setContext(conversationId: convId, contextId: nil)
        projectContextStore.activeContextId = nil
    }

    func selectThread(_ conv: Conversation) {
        selectedConversationId = conv.id
        if let contextId = conv.contextId {
            projectContextStore.activeContextId = contextId
            syncActiveWorkspaceIfNeeded(contextId: contextId)
            if conv.messages.contains(where: { $0.role == .user }) {
                projectContextStore.setLastActiveConversation(contextId: contextId, folderPath: conv.contextFolderPath, conversationId: conv.id)
            }
        }
    }

    func createThread(contextId: UUID?) {
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil

        // Reuse an existing empty thread (no user messages) with the same context
        // instead of creating duplicate blank threads.
        if let existing = chatStore.conversations.first(where: {
            !$0.isArchived
            && $0.contextId == contextId
            && $0.contextFolderPath == folderScope
            && !$0.messages.contains(where: { $0.role == .user })
        }) {
            selectedConversationId = existing.id
            if let contextId {
                projectContextStore.activeContextId = contextId
                syncActiveWorkspaceIfNeeded(contextId: contextId)
            }
            return
        }

        let newId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        selectedConversationId = newId
        if let contextId {
            projectContextStore.activeContextId = contextId
            syncActiveWorkspaceIfNeeded(contextId: contextId)
        }
    }

    func deleteWorkspace(_ ws: Workspace) {
        chatStore.clearWorkspaceReferences(workspaceId: ws.id)
        workspaceStore.delete(id: ws.id)
        projectContextStore.remove(id: ws.id)
    }

    func loadCodexTasks() {
        guard let path = codexState.status.path else { return }
        isLoadingTasks = true
        Task {
            let tasks = await CodexCloudTasks.list(codexPath: path)
            await MainActor.run {
                codexTasks = tasks
                isLoadingTasks = false
            }
        }
    }

    func handleAddFolderSelection(result: Result<[URL], Error>) {
        guard let workspaceId = pendingAddFolderWorkspaceId else { return }
        defer { pendingAddFolderWorkspaceId = nil }
        guard case .success(let urls) = result, let url = urls.first else { return }
        workspaceStore.addFolder(to: workspaceId, path: url.path(percentEncoded: false))
        projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
    }
}
