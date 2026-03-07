import Foundation

public actor ReviewSessionRegistry {
    public enum ResolutionError: Error, Sendable, Equatable {
        case notFound
        case ambiguous([String])
    }

    public static let shared = ReviewSessionRegistry()

    private var statesBySessionId: [String: CodeReviewSessionState] = [:]
    private var snapshotsBySessionId: [String: CodeReviewSessionSnapshot] = [:]
    private var sessionIdsByConversation: [String: [String]] = [:]

    public init() {}

    public func register(_ state: CodeReviewSessionState) async {
        let snapshot = await state.snapshot()
        statesBySessionId[snapshot.sessionId] = state
        recordSnapshot(snapshot)
    }

    public func unregister(sessionId: String) {
        statesBySessionId.removeValue(forKey: sessionId)
    }

    public func state(sessionId: String) -> CodeReviewSessionState? {
        statesBySessionId[sessionId]
    }

    public func recordSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        if let current = snapshotsBySessionId[snapshot.sessionId],
           shouldSkipSnapshotUpdate(current: current, incoming: snapshot) {
            return
        }
        snapshotsBySessionId[snapshot.sessionId] = snapshot
        guard let key = conversationKey(snapshot.conversationId) else { return }
        var ids = sessionIdsByConversation[key] ?? []
        ids.removeAll { $0 == snapshot.sessionId }
        ids.insert(snapshot.sessionId, at: 0)
        sessionIdsByConversation[key] = ids
    }

    public func snapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        snapshotsBySessionId[sessionId]
    }

    public func snapshots(conversationId: UUID?) -> [CodeReviewSessionSnapshot] {
        guard let key = conversationKey(conversationId) else {
            return snapshotsBySessionId.values.sorted(by: sortSnapshots)
        }
        let ids = sessionIdsByConversation[key] ?? []
        return ids.compactMap { snapshotsBySessionId[$0] }.sorted(by: sortSnapshots)
    }

    public func latestSnapshot(conversationId: UUID?) -> CodeReviewSessionSnapshot? {
        snapshots(conversationId: conversationId).first
    }

    public func resolveSessionId(
        requestedSessionId: String?,
        conversationId: UUID?,
        allowLatestFallback: Bool,
        requireExplicitWhenAmbiguous: Bool
    ) throws -> String {
        let trimmedRequested = (requestedSessionId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRequested.isEmpty {
            guard snapshotsBySessionId[trimmedRequested] != nil else {
                throw ResolutionError.notFound
            }
            return trimmedRequested
        }

        guard allowLatestFallback else {
            throw ResolutionError.notFound
        }

        let available = snapshots(conversationId: conversationId)
            .map(\.sessionId)
        guard !available.isEmpty else {
            throw ResolutionError.notFound
        }
        if requireExplicitWhenAmbiguous && available.count > 1 {
            throw ResolutionError.ambiguous(available)
        }
        return available[0]
    }

    public func applyFix(sessionId: String, findingId: String) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        return await state.applyFix(findingId: findingId)
    }

    public func dismissFinding(
        sessionId: String,
        findingId: String,
        reason: String
    ) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        return await state.dismissFinding(findingId: findingId, reason: reason)
    }

    public func addComment(
        sessionId: String,
        findingId: String,
        comment: FindingComment
    ) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        return await state.addComment(findingId: findingId, comment: comment)
    }

    public func updateConfig(
        sessionId: String,
        config: SessionConfig
    ) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        await state.updateConfig(config)
        return true
    }

    private func conversationKey(_ conversationId: UUID?) -> String? {
        conversationId?.uuidString.lowercased()
    }

    private func sortSnapshots(
        _ lhs: CodeReviewSessionSnapshot,
        _ rhs: CodeReviewSessionSnapshot
    ) -> Bool {
        if lhs.mutationSequence != rhs.mutationSequence {
            return lhs.mutationSequence > rhs.mutationSequence
        }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }
        return lhs.sessionId > rhs.sessionId
    }

    private func shouldSkipSnapshotUpdate(
        current: CodeReviewSessionSnapshot,
        incoming: CodeReviewSessionSnapshot
    ) -> Bool {
        if incoming.mutationSequence != current.mutationSequence {
            return incoming.mutationSequence < current.mutationSequence
        }
        return incoming.lastUpdatedAt < current.lastUpdatedAt
    }
}
