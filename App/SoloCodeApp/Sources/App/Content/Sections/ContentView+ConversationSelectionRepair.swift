import Foundation

extension ContentView {
    @MainActor
    func scheduleConversationSelectionRepair() {
        conversationSelectionRepairTask?.cancel()
        conversationSelectionRepairTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            repairConversationSelectionIfNeeded()
        }
    }

    @MainActor
    private func repairConversationSelectionIfNeeded() {
        let conversationIds = chatStore.conversations.map(\.id)
        guard !conversationIds.isEmpty else {
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H18",
                location: "ContentView+ConversationSelectionRepair",
                message: "conversation_ids_became_empty",
                data: [
                    "selectedConversationId": panelCoordinator.selectedConversationId?.uuidString ?? "nil",
                    "totalConversations": "\(chatStore.conversations.count)",
                ]
            )
            panelCoordinator.selectedConversationId = nil
            return
        }

        if let selectedConversationId = panelCoordinator.selectedConversationId,
           conversationIds.contains(selectedConversationId) {
            return
        }

        let defaultContextId: UUID?
        if panelCoordinator.preferActiveContextForGlobalThread {
            defaultContextId = projectContextStore.activeContextId
        } else {
            defaultContextId = nil
        }
        let context = projectContextStore.context(id: defaultContextId)
        let folderScope = (context?.folderPaths.count ?? 0) > 1 ? context?.activeFolderPath : nil
        let preferred = chatStore.conversations.first { conversation in
            !conversation.isArchived
                && conversation.contextId == defaultContextId
                && conversation.contextFolderPath == folderScope
        }?.id

        AgentDebugSessionNDJSONLog.append(
            hypothesisId: "H18",
            location: "ContentView+ConversationSelectionRepair",
            message: "selected_conversation_repaired_after_debounced_chat_update",
            data: [
                "previousSelection": panelCoordinator.selectedConversationId?.uuidString ?? "nil",
                "newSelection": (preferred ?? conversationIds.first)?.uuidString ?? "nil",
                "conversationIdsCount": "\(conversationIds.count)",
            ]
        )
        panelCoordinator.selectedConversationId = preferred ?? conversationIds.first
    }
}
