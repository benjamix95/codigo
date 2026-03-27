import Foundation

enum TodoExecutionFollowUpPolicy {
    static let reviewTitle = "Code Review & Test"
    static let docWriterTitle = "Doc Writer"
    static let scopeTitle = "Definire scope"
    static let targetAnalysisTitle = "Analizzare target"
    static let findingsConsolidationTitle = "Consolidare findings / output"

    static func normalizeExecutionTitles(_ titles: [String]) -> [String] {
        let sanitizedTitles = sanitizeMeaningfulExecutionTitles(titles)
        guard !sanitizedTitles.isEmpty else { return [] }

        if sanitizedTitles.count == 1,
           let expandedTitles = expandedSequenceIfNeeded(for: sanitizedTitles[0]) {
            return appendMissingFinalFollowUps(to: expandedTitles)
        }

        return appendMissingFinalFollowUps(to: sanitizedTitles)
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
        if isReviewTitle(item.title) { return 100 }
        if isDocWriterTitle(item.title) { return 200 }
        return 0
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
        !missingFinalFollowUpTitles(in: todos, conversationId: conversationId).isEmpty
    }

    static func missingFinalFollowUpTitles(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> [String] {
        let scopedTodos = scopedExecutionTodos(in: todos, conversationId: conversationId)
            .filter { $0.source == .agent && !$0.isOperationalPlaceholder }
        let executableTitles = scopedTodos
            .map(\.title)
            .filter { !isExecutionFollowUpTitle($0) }
            .compactMap(meaningfulExecutionTitle(from:))

        guard !executableTitles.isEmpty else {
            return []
        }

        let requiresReview = shouldRequireReviewFollowUp(forExecutableTitles: executableTitles)
        let requiresDocWriter = shouldRequireDocWriterFollowUp(forExecutableTitles: executableTitles)
        var missing: [String] = []

        if requiresReview, !scopedTodos.contains(where: { isReviewTitle($0.title) }) {
            missing.append(reviewTitle)
        }
        if requiresDocWriter, !scopedTodos.contains(where: { isDocWriterTitle($0.title) }) {
            missing.append(docWriterTitle)
        }
        return missing
    }

    static func implicitRuntimeFollowUpTitles(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> [String] {
        missingFinalFollowUpTitles(in: todos, conversationId: conversationId)
    }

    static func requiresFinalFollowUps(forExecutableTitles titles: [String]) -> Bool {
        !finalFollowUpTitles(forExecutableTitles: titles).isEmpty
    }

    static func titleRequiresFinalFollowUps(_ title: String) -> Bool {
        shouldRequireReviewFollowUp(forExecutableTitles: [title])
    }

    static func normalizedTitleKey(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
