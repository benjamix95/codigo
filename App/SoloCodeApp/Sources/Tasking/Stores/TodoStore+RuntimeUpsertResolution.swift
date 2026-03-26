import Foundation

extension TodoStore {
    /// Dopo `upsertFromAgent`, la riga aggiornata può non avere più `preferredId` se il merge è avvenuto per titolo nello stesso scope.
    func planConversationIdForRuntimeTodoAfterUpsert(
        preferredId: UUID,
        normalizedTitle: String,
        eventConversationId: UUID?
    ) -> UUID? {
        if let row = todos.first(where: { $0.id == preferredId }) {
            return row.planConversationId
        }
        let key = normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let matches = todos.filter {
            !$0.isPlanCanonical
                && !$0.isOperationalPlaceholder
                && $0.title.caseInsensitiveCompare(key) == .orderedSame
        }
        if let eventConversationId,
           let scoped = matches.first(where: { $0.planConversationId == eventConversationId }) {
            return scoped.planConversationId
        }
        return matches.first?.planConversationId
    }
}
