import Foundation

extension TodoStore {
    /// Dopo `upsertFromAgent`, la riga aggiornata può non avere più `preferredId` se il merge è avvenuto per titolo nello stesso scope.
    /// Con `preferredId == nil`, la risoluzione è solo per titolo (`updatedAt`, `createdAt`, `id`).
    /// Se `eventConversationId` è valorizzato ma nessun match ha quel `planConversationId`, restituisce `nil` (niente fallback verso altre chat).
    func planConversationIdForRuntimeTodoAfterUpsert(
        preferredId: UUID?,
        normalizedTitle: String,
        eventConversationId: UUID?
    ) -> UUID? {
        if let preferredId,
           let row = todos.first(where: { $0.id == preferredId }) {
            return row.effectiveRuntimeQueueConversationId
        }
        let key = normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let matches = todos.filter {
            !$0.isPlanCanonical
                && !$0.isOperationalPlaceholder
                && $0.title.caseInsensitiveCompare(key) == .orderedSame
        }
        guard !matches.isEmpty else { return nil }

        if let eventConversationId {
            let scoped = matches.filter {
                $0.planConversationId == eventConversationId
                    || ($0.planConversationId == nil && $0.lastTouchedConversationId == eventConversationId)
            }
            guard !scoped.isEmpty else { return nil }
            let best = scoped.max(by: Self.runtimeTodoResolutionPrefersSecond)!
            return best.effectiveRuntimeQueueConversationId ?? eventConversationId
        }
        return matches.max(by: Self.runtimeTodoResolutionPrefersSecond)?.effectiveRuntimeQueueConversationId
    }

    /// Ordine per `max(by:)` crescente: vince la riga con `updatedAt` più recente, poi `createdAt`, poi `id` lessicografico.
    private static func runtimeTodoResolutionPrefersSecond(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
