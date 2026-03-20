import Foundation
import CoderEngine

struct ChatStoreConversationDeletionOutcome: Equatable {
    let autoCreatedReplacementId: UUID?

    static let none = ChatStoreConversationDeletionOutcome(autoCreatedReplacementId: nil)
}

extension ChatStore {
    func hasUserMessages(_ conversation: Conversation) -> Bool {
        conversation.messages.contains(where: { $0.role == .user })
    }

    func reusableEmptyConversation(
        contextId: UUID?,
        contextFolderPath: String?,
        mode: CoderMode? = nil
    ) -> Conversation? {
        conversations.first { conv in
            !conv.isArchived
                && conv.contextId == contextId
                && conv.contextFolderPath == contextFolderPath
                && conv.mode == mode
                && !hasUserMessages(conv)
        }
    }

    @discardableResult
    func createConversation(contextId: UUID? = nil, contextFolderPath: String? = nil, mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
            conversations.append(conv)
        } else {
            _ = applyRustStoreAction("create_conversation") { request in
                request.conversation = RustMainChatStoreAdapter.conversationSnapshot(conv)
            }
        }
        saveConversations()
        return conv.id
    }

    // Legacy wrappers for callers still using old API.
    @discardableResult
    func createConversation(workspaceId: UUID? = nil, adHocFolderPaths: [String] = [], mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: workspaceId, mode: mode, workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths)
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
            conversations.append(conv)
        } else {
            _ = applyRustStoreAction("create_conversation") { request in
                request.conversation = RustMainChatStoreAdapter.conversationSnapshot(conv)
            }
        }
        saveConversations()
        return conv.id
    }

    func conversationForMode(contextId: UUID?, contextFolderPath: String? = nil, mode: CoderMode) -> Conversation? {
        conversations.first { conv in
            conv.contextId == contextId && conv.mode == mode && (contextFolderPath == nil || conv.contextFolderPath == contextFolderPath)
        }
    }

    @discardableResult
    func getOrCreateConversationForMode(contextId: UUID?, contextFolderPath: String? = nil, mode: CoderMode) -> UUID {
        if let existing = conversationForMode(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode) {
            return existing.id
        }
        return createConversation(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
    }

    // Legacy wrappers for old callers.
    func conversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> Conversation? {
        conversations.first { conv in
            conv.contextId == workspaceId && conv.mode == mode && (adHocFolderPaths.isEmpty || Set(conv.adHocFolderPaths) == Set(adHocFolderPaths))
        }
    }

    @discardableResult
    func getOrCreateConversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> UUID {
        if let existing = conversationForMode(workspaceId: workspaceId, mode: mode, adHocFolderPaths: adHocFolderPaths) {
            return existing.id
        }
        return createConversation(workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths, mode: mode)
    }

    @discardableResult
    func deleteConversation(id: UUID) -> ChatStoreConversationDeletionOutcome {
        _ = applyRustStoreAction("delete_conversation") { request in
            request.conversationId = id.uuidString.lowercased()
        }
        planSharedSyncSignatureByConversation.removeValue(forKey: id)
        draftTexts.removeValue(forKey: id)
        activeTaskConversationIds.remove(id)
        taskStartDates.removeValue(forKey: id)
        taskStatusTexts.removeValue(forKey: id)
        let autoCreatedReplacementId: UUID?
        if conversations.isEmpty {
            autoCreatedReplacementId = createConversation(
                contextId: nil,
                contextFolderPath: nil,
                mode: nil
            )
        } else {
            autoCreatedReplacementId = nil
        }
        saveConversations()
        savePlanBoards()
        return ChatStoreConversationDeletionOutcome(
            autoCreatedReplacementId: autoCreatedReplacementId
        )
    }

    func setPinned(conversationId: UUID, pinned: Bool) {
        _ = applyRustStoreAction("set_pinned") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = pinned
        }
        saveConversations()
    }

    func setFavorite(conversationId: UUID, favorite: Bool) {
        _ = applyRustStoreAction("set_favorite") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = favorite
        }
        saveConversations()
    }

    func setArchived(conversationId: UUID, archived: Bool) {
        _ = applyRustStoreAction("set_archived") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = archived
        }
        saveConversations()
    }

    func setTitle(conversationId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = applyRustStoreAction("set_title") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.title = trimmed
        }
        saveConversations()
    }

    func updateConversationMode(conversationId: UUID?, mode: CoderMode?) {
        guard let id = conversationId else { return }
        _ = applyRustStoreAction("set_mode") { request in
            request.conversationId = id.uuidString.lowercased()
            request.mode = mode?.rawValue
        }
        saveConversations()
    }

    func updatePreferredProvider(conversationId: UUID?, providerId: String?) {
        guard let id = conversationId else { return }
        _ = applyRustStoreAction("set_preferred_provider") { request in
            request.conversationId = id.uuidString.lowercased()
            request.providerId = providerId
        }
        saveConversations()
    }

    func searchThreads(query: String, includeArchived: Bool = true, limit: Int = 50) -> [ThreadSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [ThreadSearchHit] = []

        for conv in conversations {
            if !includeArchived, conv.isArchived { continue }
            var score = 0
            var snippet = conv.title
            let titleLower = conv.title.lowercased()
            if titleLower.contains(q) { score += 2 }

            let assistantAndUser = conv.messages.map(\.content).joined(separator: "\n")
            let bodyLower = assistantAndUser.lowercased()
            if let range = assistantAndUser.range(of: q, options: .caseInsensitive) {
                score += 1
                let idx = assistantAndUser.distance(from: assistantAndUser.startIndex, to: range.lowerBound)
                let start = max(0, idx - 60)
                let end = min(assistantAndUser.count, idx + 140)
                let sIdx = assistantAndUser.index(assistantAndUser.startIndex, offsetBy: start)
                let eIdx = assistantAndUser.index(assistantAndUser.startIndex, offsetBy: end)
                snippet = String(assistantAndUser[sIdx..<eIdx]).replacingOccurrences(of: "\n", with: " ")
            }

            guard score > 0 else { continue }
            let count = titleLower.components(separatedBy: q).count - 1 + bodyLower.components(separatedBy: q).count - 1
            hits.append(ThreadSearchHit(
                id: conv.id,
                conversationId: conv.id,
                title: conv.title,
                snippet: snippet,
                matchCount: max(1, count),
                isArchived: conv.isArchived,
                isFavorite: conv.isFavorite
            ))
        }

        return hits.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            if $0.matchCount != $1.matchCount { return $0.matchCount > $1.matchCount }
            return $0.title < $1.title
        }.prefix(limit).map { $0 }
    }

    func buildThreadSearchAIPrompt(query: String, hits: [ThreadSearchHit], maxItems: Int = 12) -> String {
        let items = hits.prefix(maxItems).map {
            "- Thread: \($0.title)\n  Match: \($0.matchCount)\n  Snippet: \($0.snippet)"
        }.joined(separator: "\n")
        return """
        Use exclusively the context of the threads found below to answer my question.
        If the context is not enough, state it clearly.

        Search query: \(query)

        Thread results:
        \(items)

        Question:
        """
    }

    func clearWorkspaceReferences(workspaceId: UUID) {
        conversations = conversations.map { conv in
            guard conv.contextId == workspaceId || conv.workspaceId == workspaceId else { return conv }
            var updated = conv
            updated.contextId = nil
            updated.workspaceId = nil
            updated.adHocFolderPaths = []
            return updated
        }
        saveConversations()
    }

    func setContext(conversationId: UUID?, contextId: UUID?) {
        guard let conversationId else { return }
        _ = applyRustStoreAction("set_context") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.contextId = contextId?.uuidString.lowercased()
            request.workspaceId = contextId?.uuidString.lowercased()
            request.contextFolderPath = nil
            request.stringList = []
        }
        saveConversations()
    }

    func setContextFolder(conversationId: UUID?, folderPath: String?) {
        guard let conversationId else { return }
        _ = applyRustStoreAction("set_context_folder") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.contextFolderPath = folderPath
        }
        saveConversations()
    }

    func setWorkspace(conversationId: UUID?, workspaceId: UUID?) {
        setContext(conversationId: conversationId, contextId: workspaceId)
    }

    func setAdHocPaths(conversationId: UUID?, paths: [String]) {
        guard let conversationId else { return }
        _ = applyRustStoreAction("set_ad_hoc_paths") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.contextId = nil
            request.contextFolderPath = nil
            request.workspaceId = nil
            request.stringList = paths
        }
        saveConversations()
    }

    func conversation(for id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    func isAssistantStreaming(in conversationId: UUID?) -> Bool {
        guard let conversation = conversation(for: conversationId) else { return false }
        guard let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) else {
            return false
        }
        return lastAssistant.isStreaming
    }
}
