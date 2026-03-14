import Foundation

enum VerifiedFindingsPatchCommandError: LocalizedError {
    case reviewNotVerified
    case findingNotClosable

    var errorDescription: String? {
        switch self {
        case .reviewNotVerified:
            return "Finding is not verified or available."
        case .findingNotClosable:
            return "Finding cannot be closed until the patch is validated or the finding is already resolved."
        }
    }
}

public struct VerifiedFindingsSessionEnvelope: Sendable, Codable, Equatable {
    public let sessionId: String
    public let canonicalSnapshot: VerifiedFindingsCanonicalSnapshot
    public let projectionSnapshot: VerifiedFindingsProjectionSnapshot
    public let eventSchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let lastUpdatedAt: Date

    public init(
        sessionId: String,
        canonicalSnapshot: VerifiedFindingsCanonicalSnapshot,
        projectionSnapshot: VerifiedFindingsProjectionSnapshot,
        eventSchemaVersion: Int = 1,
        projectionSchemaVersion: Int = 1,
        entitySchemaVersion: Int = 1,
        lastUpdatedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.canonicalSnapshot = canonicalSnapshot
        self.projectionSnapshot = projectionSnapshot
        self.eventSchemaVersion = eventSchemaVersion
        self.projectionSchemaVersion = projectionSchemaVersion
        self.entitySchemaVersion = entitySchemaVersion
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct VerifiedFindingsResolvedState: Sendable, Equatable {
    public let recovered: VerifiedFindingsRecoveredEnvelope
    public let securityGate: VerifiedFindingsSecurityGateReport
    public let replayReport: VerifiedFindingsReplayReport

    public init(
        recovered: VerifiedFindingsRecoveredEnvelope,
        securityGate: VerifiedFindingsSecurityGateReport,
        replayReport: VerifiedFindingsReplayReport
    ) {
        self.recovered = recovered
        self.securityGate = securityGate
        self.replayReport = replayReport
    }
}

public struct VerifiedFindingsReplayReport: Sendable, Codable, Equatable {
    public let sessionId: String
    public let checkpointSource: VerifiedFindingsEnvelopeSource
    public let eventSchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let findingCount: Int
    public let eventCount: Int
    public let traceCount: Int
    public let candidateCount: Int
    public let verifiedCount: Int
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
}

public enum VerifiedFindingsService {
    public static func resolve(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsResolvedState {
        let recovered = VerifiedFindingsCheckpointService.resolveEnvelope(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        return resolve(recovered: recovered)
    }

    public static func resolve(
        sessionId: String,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsResolvedState? {
        if let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) {
            return resolve(snapshot: snapshot, entryPoint: entryPoint)
        }
        guard let recovered = VerifiedFindingsCheckpointService.rebuildEnvelope(sessionId: sessionId) else {
            return nil
        }
        return resolve(recovered: recovered)
    }

    public static func resolve(
        recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsResolvedState {
        VerifiedFindingsResolvedState(
            recovered: recovered,
            securityGate: VerifiedFindingsSecurityGateService.evaluate(
                envelope: recovered.envelope
            ),
            replayReport: replay(recovered)
        )
    }

    public static func projection(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsProjectionSnapshot {
        resolve(snapshot: snapshot, entryPoint: entryPoint).recovered.envelope.projectionSnapshot
    }

    public static func canonicalSnapshot(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsCanonicalSnapshot {
        resolve(snapshot: snapshot, entryPoint: entryPoint).recovered.envelope.canonicalSnapshot
    }

    public static func replay(
        sessionId: String
    ) -> VerifiedFindingsReplayReport? {
        guard let recovered = VerifiedFindingsCheckpointService.rebuildEnvelope(sessionId: sessionId) else {
            return nil
        }
        return replay(recovered)
    }

    public static func replay(
        _ recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsReplayReport {
        if let bridged = replayWithRust(recovered) {
            return bridged
        }
        let projection = VerifiedFindingsProjectionBuilder.build(
            from: recovered.envelope.canonicalSnapshot
        )
        return VerifiedFindingsReplayReport(
            sessionId: recovered.envelope.sessionId,
            checkpointSource: recovered.source,
            eventSchemaVersion: recovered.envelope.eventSchemaVersion,
            projectionSchemaVersion: recovered.envelope.projectionSchemaVersion,
            entitySchemaVersion: recovered.envelope.entitySchemaVersion,
            findingCount: recovered.envelope.canonicalSnapshot.findings.count,
            eventCount: recovered.envelope.canonicalSnapshot.eventLog.count,
            traceCount: recovered.envelope.canonicalSnapshot.traceLog.count,
            candidateCount: projection.candidateQueue.count,
            verifiedCount: projection.verifiedQueue.count,
            duplicatesCount: projection.duplicatesCount,
            staleCandidatesCount: projection.staleCandidatesCount
        )
    }

    public static func upsertingPatch(
        in snapshot: CodeReviewSessionSnapshot,
        artifact: ReviewPatchArtifact
    ) -> CodeReviewSessionSnapshot {
        var patches = snapshot.patches
        if let index = patches.firstIndex(where: { $0.id == artifact.id || $0.findingId == artifact.findingId }) {
            patches[index] = artifact
        } else {
            patches.append(artifact)
        }

        var findings = snapshot.findings
        if let index = findings.firstIndex(where: { $0.id == artifact.findingId }) {
            findings[index].patchArtifactId = artifact.id
            findings[index].status = switch artifact.status {
            case .draft: .patchPreparing
            case .verified: .patchReady
            case .applied: .patchApplied
            case .applyFailed: .patchFailed
            case .prOpened: .prOpened
            case .merged: .merged
            case .conflict, .rolledBack: .blocked
            }
        }

        return snapshot.copying(
            findings: findings,
            patches: patches,
            events: snapshot.events + [
                CodeReviewSessionEvent.patchPrepared(
                    patchId: artifact.id,
                    findingId: artifact.findingId
                ),
            ],
            outcome: snapshot.copying(findings: findings, patches: patches).buildOutcomeSummary()
        )
    }

    public static func closeFinding(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String
    ) throws -> CodeReviewSessionSnapshot {
        guard let findingIndex = snapshot.findings.firstIndex(where: { $0.id == findingId }) else {
            throw VerifiedFindingsPatchCommandError.reviewNotVerified
        }
        let currentStatus = snapshot.findings[findingIndex].status
        let patch = snapshot.findings[findingIndex].patchArtifactId.flatMap { patchId in
            snapshot.patches.first(where: { $0.id == patchId })
        } ?? snapshot.patches.first(where: { $0.findingId == findingId })

        let canClose: Bool
        switch currentStatus {
        case .merged, .dismissed, .wontFix, .closed:
            canClose = true
        case .patchApplied, .fixApplied:
            canClose = patch?.validationStatus == .passed
        default:
            canClose = false
        }
        guard canClose else {
            throw VerifiedFindingsPatchCommandError.findingNotClosable
        }

        var findings = snapshot.findings
        findings[findingIndex].status = .closed
        let updated = snapshot.copying(
            findings: findings,
            events: snapshot.events + [
                CodeReviewSessionEvent(
                    type: .outcomePublished,
                    detail: "Finding \(findingId) closed",
                    metadata: ["finding_id": findingId, "reason": "closed"]
                )
            ]
        )
        return updated.copying(
            mutationSequence: updated.mutationSequence,
            outcome: updated.buildOutcomeSummary(),
            lastUpdatedAt: Date()
        )
    }

    private static func replayWithRust(
        _ recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsReplayReport? {
        let request = ReviewCoreReplayRequest(
            schemaVersion: 1,
            envelope: recovered.envelope,
            checkpointSource: recovered.source.rawValue
        )
        let response: ReviewCoreReplayBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_replay_verified_findings",
            request: request
        )
        return response?.report
    }
}

private struct ReviewCoreReplayRequest: Encodable {
    let schemaVersion: Int
    let envelope: VerifiedFindingsSessionEnvelope
    let checkpointSource: String
}

private struct ReviewCoreReplayBridgeResponse: Decodable {
    let report: VerifiedFindingsReplayReport?
}
