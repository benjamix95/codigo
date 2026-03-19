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
        guard let updated = ReviewSessionRustBridge.applyRegistryAction(
            operation: "configure",
            snapshot: snapshot,
            payload: config.reviewCommandPayload
        ) else {
            return false
        }
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
        guard let updated = ReviewSessionRustBridge.applyRegistryAction(
            operation: action,
            snapshot: snapshot,
            payload: payload
        ) else {
            return false
        }
        await state.replaceCanonicalSnapshot(updated)
        recordSnapshot(updated)
        return true
    }
}

struct ReviewSessionRustBridge {
    static func newSnapshot(
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionSnapshot? {
        let response: ReviewSessionRustResponse? = ReviewCoreBridge.call(
            functionName: "review_core_session_snapshot_new",
            request: ReviewSessionRustNewSnapshotRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                conversationId: conversationId?.uuidString.lowercased(),
                config: config
            )
        )
        guard response?.error == nil else { return nil }
        return response?.snapshot
    }

    static func applyAction(
        _ request: ReviewSessionRustActionRequest
    ) -> CodeReviewSessionSnapshot? {
        let response: ReviewSessionRustResponse? = ReviewCoreBridge.call(
            functionName: "review_core_session_apply_action",
            request: request
        )
        guard response?.error == nil else { return nil }
        return response?.snapshot
    }

    static func applyRegistryAction(
        operation: String,
        snapshot: CodeReviewSessionSnapshot,
        payload: [String: String]
    ) -> CodeReviewSessionSnapshot? {
        let response: ReviewSessionRustResponse? = ReviewCoreBridge.call(
            functionName: "review_core_registry_apply_action",
            request: ReviewSessionRustRegistryRequest(
                schemaVersion: 1,
                operation: operation,
                snapshot: snapshot,
                payload: payload
            )
        )
        guard response?.error == nil else { return nil }
        return response?.snapshot
    }
}

private struct ReviewSessionRustNewSnapshotRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let conversationId: String?
    let config: SessionConfig
}

struct ReviewSessionRustActionRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
    var scope: ReviewSessionScope?
    var workspacePath: String?
    var finding: CodeReviewFinding?
    var findings: [CodeReviewFinding]?
    var candidate: ReviewCandidate?
    var candidates: [ReviewCandidate]?
    var candidateId: String?
    var findingId: String?
    var patch: ReviewPatchArtifact?
    var reason: String?
    var comment: FindingComment?
    var config: SessionConfig?
    var round: Int?
    var count: Int?
    var phase: ReviewSessionPhase?
    var stage: ReviewSessionStage?
    var jobId: String?
    var toolName: String?
    var auditResult: ReviewAuditToolResult?
    var workerId: String?
    var title: String?
    var status: ReviewCandidateStatus?
    var method: String?
    var report: String?
    var falsePositiveReason: String?
    var resultDetail: String?
    var testStatus: ReviewSessionTestStatus?
    var files: [String]?
    var error: String?
}

private struct ReviewSessionRustRegistryRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
    let payload: [String: String]
}

private struct ReviewSessionRustResponse: Decodable {
    let error: ReviewSessionRustError?
    let snapshot: CodeReviewSessionSnapshot?
}

private struct ReviewSessionRustError: Decodable {
    let code: String
    let message: String
}
