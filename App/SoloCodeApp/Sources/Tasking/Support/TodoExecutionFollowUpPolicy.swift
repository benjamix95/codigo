import Foundation

enum TodoExecutionFollowUpPolicy {
    static let reviewTitle = "Code Review & Test"
    static let docWriterTitle = "Doc Writer"

    static func normalizeExecutionTitles(_ titles: [String]) -> [String] {
        var seenKeys = Set<String>()
        var executableTitles: [String] = []

        for raw in titles {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !isExecutionFollowUpTitle(trimmed) else { continue }

            let key = normalizedTitleKey(trimmed)
            guard seenKeys.insert(key).inserted else { continue }
            executableTitles.append(trimmed)
        }

        guard !executableTitles.isEmpty else { return [] }
        guard requiresFinalFollowUps(forExecutableTitles: executableTitles) else {
            return executableTitles
        }

        executableTitles.append(reviewTitle)
        executableTitles.append(docWriterTitle)
        return executableTitles
    }

    static func isReviewTitle(_ title: String) -> Bool {
        normalizedTitleKey(title) == normalizedTitleKey(reviewTitle)
    }

    static func isDocWriterTitle(_ title: String) -> Bool {
        normalizedTitleKey(title) == normalizedTitleKey(docWriterTitle)
    }

    static func isExecutionFollowUpTitle(_ title: String) -> Bool {
        isReviewTitle(title) || isDocWriterTitle(title)
    }

    static func autoCompletionRank(for title: String) -> Int {
        if isReviewTitle(title) { return 1 }
        if isDocWriterTitle(title) { return 2 }
        return 0
    }

    static func runtimeOrderRank(for item: TodoItem) -> Int {
        let followUpBase: Int = {
            if isReviewTitle(item.title) { return 100 }
            if isDocWriterTitle(item.title) { return 200 }
            return 0
        }()
        switch item.status {
        case .inProgress:
            return followUpBase
        case .pending:
            return followUpBase + 10
        case .blocked:
            return followUpBase + 20
        case .done:
            return followUpBase + 30
        }
    }

    static func scopedExecutionTodos(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> [TodoItem] {
        let visible = todos.filter { !$0.isOperationalPlaceholder }
        guard let conversationId else { return visible }
        let planScopeIds = Set(visible.compactMap(\.planConversationId))
        return visible.filter {
            TodoChatDisplayPolicy.itemAppearsInChat(
                $0,
                conversationId: conversationId,
                visibleTodos: visible,
                planScopeIds: planScopeIds
            )
        }
    }

    static func shouldCreateFinalFollowUps(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> Bool {
        scopedExecutionTodos(in: todos, conversationId: conversationId).contains { item in
            item.source == .agent
                && !item.isOperationalPlaceholder
                && !isExecutionFollowUpTitle(item.title)
                && titleRequiresFinalFollowUps(item.title)
        }
    }

    static func missingFinalFollowUpTitles(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> [String] {
        guard shouldCreateFinalFollowUps(in: todos, conversationId: conversationId) else {
            return []
        }
        let scoped = scopedExecutionTodos(in: todos, conversationId: conversationId)
        var missing: [String] = []
        if !scoped.contains(where: { isReviewTitle($0.title) }) {
            missing.append(reviewTitle)
        }
        if !scoped.contains(where: { isDocWriterTitle($0.title) }) {
            missing.append(docWriterTitle)
        }
        return missing
    }

    static func requiresFinalFollowUps(forExecutableTitles titles: [String]) -> Bool {
        titles.contains(where: titleRequiresFinalFollowUps(_:))
    }

    static func titleRequiresFinalFollowUps(_ title: String) -> Bool {
        let normalized = normalizedTitleKey(title)
        guard !normalized.isEmpty else { return false }
        guard !isExecutionFollowUpTitle(title) else { return false }

        let mutationSignals = [
            "implement",
            "fix",
            "refactor",
            "update",
            "modify",
            "edit",
            "patch",
            "add",
            "remove",
            "delete",
            "rename",
            "replace",
            "create file",
            "split",
            "migrate",
            "wire",
            "integrate",
            "write code",
            "correggere",
            "implementare",
            "rifattorizzare",
            "aggiornare",
            "modificare",
            "editare",
            "aggiungere",
            "rimuovere",
            "eliminare",
            "rinominare",
            "sostituire",
            "creare file",
            "dividere",
            "migrare",
            "collegare",
            "integrare",
        ]

        return mutationSignals.contains { normalized.contains($0) }
    }

    private static func normalizedTitleKey(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
