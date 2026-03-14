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
        snapshotsBySessionId.removeValue(forKey: sessionId)
        for key in sessionIdsByConversation.keys {
            sessionIdsByConversation[key]?.removeAll { $0 == sessionId }
            if sessionIdsByConversation[key]?.isEmpty == true {
                sessionIdsByConversation.removeValue(forKey: key)
            }
        }
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
        await mutateLiveSession(
            sessionId: sessionId,
            action: "apply_fix",
            payload: ["finding_id": findingId]
        )
    }

    public func dismissFinding(
        sessionId: String,
        findingId: String,
        reason: String
    ) async -> Bool {
        await mutateLiveSession(
            sessionId: sessionId,
            action: "dismiss",
            payload: ["finding_id": findingId, "reason": reason]
        )
    }

    public func addComment(
        sessionId: String,
        findingId: String,
        comment: FindingComment
    ) async -> Bool {
        await mutateLiveSession(
            sessionId: sessionId,
            action: "comment",
            payload: [
                "finding_id": findingId,
                "author": comment.author,
                "content": comment.content,
            ]
        )
    }

    public func updateConfig(
        sessionId: String,
        config: SessionConfig
    ) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        let snapshot = await state.snapshot()
        guard let response: ReviewSessionRegistryMutationResponse = ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewSessionRegistryMutationRequest(
                schemaVersion: 1,
                action: "configure",
                snapshot: snapshot,
                payload: config.reviewCommandPayload
            )
        ),
              !response.isError,
              let updatedConfig = response.config,
              let events = response.events else {
            await state.updateConfig(config)
            recordSnapshot(await state.snapshot())
            return true
        }
        let updated = snapshot.copying(
            events: events,
            config: updatedConfig,
            outcome: snapshot.copying(events: events, config: updatedConfig).buildOutcomeSummary()
        )
        await state.replaceCanonicalSnapshot(updated)
        recordSnapshot(updated)
        return true
    }

    private func conversationKey(_ conversationId: UUID?) -> String? {
        conversationId?.uuidString.lowercased()
    }

    private func sortSnapshots(
        _ lhs: CodeReviewSessionSnapshot,
        _ rhs: CodeReviewSessionSnapshot
    ) -> Bool {
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }
        if lhs.mutationSequence != rhs.mutationSequence {
            return lhs.mutationSequence > rhs.mutationSequence
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

    private func mutateLiveSession(
        sessionId: String,
        action: String,
        payload: [String: String]
    ) async -> Bool {
        guard let state = statesBySessionId[sessionId] else { return false }
        let snapshot = await state.snapshot()
        guard let response: ReviewSessionRegistryMutationResponse = ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewSessionRegistryMutationRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                payload: payload
            )
        ),
              !response.isError,
              let findings = response.findings,
              let events = response.events else {
            return await mutateLiveSessionFallback(
                state: state,
                snapshot: snapshot,
                action: action,
                payload: payload
            )
        }

        let updated = snapshot.copying(
            findings: findings,
            events: events,
            outcome: snapshot.copying(findings: findings, events: events).buildOutcomeSummary()
        )
        await state.replaceCanonicalSnapshot(updated)
        recordSnapshot(updated)
        return true
    }

    private func mutateLiveSessionFallback(
        state: CodeReviewSessionState,
        snapshot: CodeReviewSessionSnapshot,
        action: String,
        payload: [String: String]
    ) async -> Bool {
        let findingId = payload["finding_id"] ?? ""
        let didChange: Bool = switch action {
        case "apply_fix":
            await state.applyFix(findingId: findingId)
        case "dismiss":
            await state.dismissFinding(
                findingId: findingId,
                reason: payload["reason"] ?? "dismissed"
            )
        case "comment":
            await state.addComment(
                findingId: findingId,
                comment: FindingComment(
                    author: payload["author"] ?? "system",
                    content: payload["content"] ?? ""
                )
            )
        default:
            false
        }
        guard didChange else { return false }
        recordSnapshot(await state.snapshot())
        return true
    }
}

private struct ReviewSessionRegistryMutationRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let snapshot: CodeReviewSessionSnapshot
    let payload: [String: String]
}

private struct ReviewSessionRegistryMutationResponse: Decodable {
    let isError: Bool
    let config: SessionConfig?
    let findings: [CodeReviewFinding]?
    let events: [CodeReviewSessionEvent]?
}
