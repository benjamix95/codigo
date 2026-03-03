import Foundation
import CoderEngine

extension ChatStore {
    @discardableResult
    func createConversation(contextId: UUID? = nil, contextFolderPath: String? = nil, mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
        conversations.append(conv)
        saveConversations()
        return conv.id
    }

    // Legacy wrappers for callers still using old API.
    @discardableResult
    func createConversation(workspaceId: UUID? = nil, adHocFolderPaths: [String] = [], mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: workspaceId, mode: mode, workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths)
        conversations.append(conv)
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

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        planBoards.removeValue(forKey: id)
        draftTexts.removeValue(forKey: id)
        activeTaskConversationIds.remove(id)
        taskStartDates.removeValue(forKey: id)
        taskStatusTexts.removeValue(forKey: id)
        if conversations.isEmpty { createConversation(contextId: nil, contextFolderPath: nil, mode: nil) }
        saveConversations()
        savePlanBoards()
    }

    func setPinned(conversationId: UUID, pinned: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isPinned = pinned
        saveConversations()
    }

    func setFavorite(conversationId: UUID, favorite: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isFavorite = favorite
        saveConversations()
    }

    func setArchived(conversationId: UUID, archived: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isArchived = archived
        saveConversations()
    }

    func setTitle(conversationId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].title = trimmed
        saveConversations()
    }

    func updateConversationMode(conversationId: UUID?, mode: CoderMode?) {
        guard let id = conversationId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        if conversations[idx].mode == mode {
            return
        }
        conversations[idx].mode = mode
        saveConversations()
    }

    func updatePreferredProvider(conversationId: UUID?, providerId: String?) {
        guard let id = conversationId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].preferredProviderId = providerId?.isEmpty == true ? nil : providerId
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
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextId = contextId
        conversations[idx].contextFolderPath = nil
        conversations[idx].workspaceId = contextId
        conversations[idx].adHocFolderPaths = []
        saveConversations()
    }

    func setContextFolder(conversationId: UUID?, folderPath: String?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextFolderPath = folderPath
        saveConversations()
    }

    func setWorkspace(conversationId: UUID?, workspaceId: UUID?) {
        setContext(conversationId: conversationId, contextId: workspaceId)
    }

    func setAdHocPaths(conversationId: UUID?, paths: [String]) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextId = nil
        conversations[idx].contextFolderPath = nil
        conversations[idx].workspaceId = nil
        conversations[idx].adHocFolderPaths = paths
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
