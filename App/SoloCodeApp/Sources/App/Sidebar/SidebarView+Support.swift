import SwiftUI
import CoderEngine

func isValidThreadCreationContext(_ context: ProjectContext?) -> Bool {
    guard let context else { return false }
    let effective = EffectiveContext(
        contextId: context.id,
        folderPaths: context.folderPaths,
        isWorkspace: context.kind == .workspace,
        context: context
    )
    return effective.hasSendableProjectContext
}

// MARK: - Computed State

extension SidebarView {
    var activeContext: ProjectContext? {
        if let conversation = chatStore.conversation(for: selectedConversationId),
           let contextId = conversation.contextId {
            return projectContextStore.context(id: contextId)
        }
        if preferActiveContextForGlobalThread {
            return projectContextStore.activeContext
        }
        return nil
    }

    var orderedContexts: [ProjectContext] {
        projectContextStore.contexts.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var filteredContexts: [ProjectContext] {
        guard !query.isEmpty else { return orderedContexts }
        let q = query.lowercased()
        return orderedContexts.filter { $0.name.lowercased().contains(q) }
    }

    var visibleThreads: [Conversation] {
        threadsSnapshot.threads
    }

    @MainActor
    func scheduleSidebarSnapshotRefresh() {
        sidebarSnapshotRefreshTask?.cancel()
        sidebarSnapshotRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let update = SidebarThreadSnapshotBuilder.buildSnapshotAndFingerprint(
                chatStore: chatStore,
                contextId: activeContext?.id,
                query: query,
                showArchived: showArchived,
                favoritesOnly: favoritesOnly
            )
            guard update.fingerprint != sidebarSnapshotFingerprint else {
                scheduleSidebarRenderStateRefresh()
                return
            }
            sidebarSnapshotFingerprint = update.fingerprint
            sidebarRenderFingerprint = nil
            threadsSnapshot = update.snapshot
            scheduleSidebarRenderStateRefresh()
        }
    }

    @MainActor
    func scheduleSidebarRenderStateRefresh() {
        let conversations = threadsSnapshot.threads
        sidebarRenderStateRefreshTask?.cancel()
        sidebarRenderStateRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let update = SidebarThreadSnapshotBuilder.buildRenderStatesAndFingerprint(
                conversations: conversations,
                chatStore: chatStore,
                todoStore: todoStore,
                toolTraceStore: toolTraceStore
            )
            guard update.fingerprint != sidebarRenderFingerprint else { return }
            sidebarRenderFingerprint = update.fingerprint
            threadRenderStates = update.renderStates
        }
    }
}

// MARK: - Actions

extension SidebarView {
    func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))

        let context = projectContextStore.context(id: contextId)
        guard isValidThreadCreationContext(context) else {
            showWorkspaceRequiredAlert = true
            return
        }
        let folderScope = scopedFolderPath(for: context)

        // Reuse current empty thread if possible
        if let selectedId = selectedConversationId,
           let selected = chatStore.conversation(for: selectedId),
           !selected.isArchived,
           !chatStore.hasUserMessages(selected) {
            if selected.contextId != contextId || selected.contextFolderPath != folderScope {
                chatStore.setContext(conversationId: selectedId, contextId: contextId)
                chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
            }
            return
        }

        // Try last active conversation
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived,
           chatStore.hasUserMessages(lastConv) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
    }

    func createThread(contextId: UUID?) {
        let effectiveContextId = contextId ?? activeContext?.id
        let context = projectContextStore.context(id: effectiveContextId)
        guard isValidThreadCreationContext(context) else {
            showWorkspaceRequiredAlert = true
            return
        }
        let folderScope = scopedFolderPath(for: context)

        // Azione esplicita "New Thread": crea sempre un nuovo thread. Il riuso di conversazioni
        // vuote resta per altri flussi (invio, cambio contesto) tramite `reusableEmptyConversation`.
        selectedConversationId = chatStore.createConversation(
            contextId: effectiveContextId,
            contextFolderPath: folderScope
        )
        if let effectiveContextId {
            projectContextStore.activeContextId = effectiveContextId
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: effectiveContextId))
        }
    }

    func selectConversation(_ conversation: Conversation) {
        selectedConversationId = conversation.id
        if let contextId = conversation.contextId {
            projectContextStore.activeContextId = contextId
            projectContextStore.markAsRecentlyUsed(contextId: contextId)
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
            if conversation.messages.contains(where: { $0.role == .user }) {
                projectContextStore.setLastActiveConversation(
                    contextId: contextId,
                    folderPath: conversation.contextFolderPath,
                    conversationId: conversation.id
                )
            }
        }
    }

    func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setContext(conversationId: convId, contextId: nil)
        projectContextStore.activeContextId = nil
    }

    func deleteContext(_ context: ProjectContext) {
        chatStore.clearWorkspaceReferences(workspaceId: context.id)
        workspaceStore.delete(id: context.id)
        projectContextStore.remove(id: context.id)
        if activeContext?.id == context.id {
            clearConversationContext()
        }
    }

    func scopedFolderPath(for context: ProjectContext?) -> String? {
        guard let context else { return nil }
        return context.folderPaths.count > 1 ? context.activeFolderPath : nil
    }

}

// MARK: - Date Formatting

extension SidebarView {
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    func relativeDate(_ date: Date, relativeTo ref: Date = Date()) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: ref)
    }
}
