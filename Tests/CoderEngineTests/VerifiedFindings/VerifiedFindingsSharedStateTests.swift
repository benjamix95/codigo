import XCTest
@testable import CoderEngine

final class VerifiedFindingsSharedStateTests: XCTestCase {
    private let stableDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
        try super.tearDownWithError()
    }

    func testVerifiedFindingsEnvelopeRoundTrip() {
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [:],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: ["trace"]
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: ["trace"]
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let loaded = MCPSharedState.readVerifiedFindingsEnvelope(sessionId: "session-1")

        XCTAssertEqual(loaded, envelope)
    }

    func testVerifiedFindingsEnvelopeRebuildsFromCanonicalSnapshotFallback() {
        let finding = VerifiedFinding(
            id: "finding-1",
            domain: .bug,
            title: "Crash",
            summary: "Crash on retry",
            category: "correctness",
            severity: .high,
            confidence: 0.92,
            status: .verified,
            filePath: "Sources/App.swift",
            originEntryPoint: .mainChat,
            findingFingerprint: "fp-1",
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [finding.id: finding],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: ["trace-a", "trace-b"]
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: []
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        try? FileManager.default.removeItem(
            at: MCPSharedState.verifiedFindingsEnvelopeFilePath(sessionId: "session-1")
        )

        let rebuilt = MCPSharedState.readVerifiedFindingsEnvelope(sessionId: "session-1")

        XCTAssertNotNil(rebuilt)
        XCTAssertEqual(rebuilt?.canonicalSnapshot, canonical)
        XCTAssertEqual(rebuilt?.projectionSnapshot.verifiedQueue.map(\.id), [finding.id])
        XCTAssertEqual(rebuilt?.projectionSnapshot.traceSnippets, ["trace-a", "trace-b"])
    }

    func testVerifiedFindingsCheckpointRoundTrip() {
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [:],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [
                VerifiedPipelineEvent(
                    id: "event-1",
                    runId: "run-1",
                    entityId: "finding-1",
                    entityType: .finding,
                    eventType: "finding.verified",
                    payload: ["status": "verified"],
                    eventSchemaVersion: 1,
                    entitySchemaVersion: 1,
                    migrationHint: nil,
                    createdAt: stableDate
                ),
            ],
            traceLog: ["trace-1", "trace-2"]
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: ["trace-2"]
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let checkpoint = MCPSharedState.readVerifiedFindingsCheckpoint(sessionId: "session-1")

        XCTAssertNotNil(checkpoint)
        XCTAssertEqual(checkpoint?.sessionId, "session-1")
        XCTAssertEqual(checkpoint?.eventSchemaVersion, envelope.eventSchemaVersion)
        XCTAssertEqual(checkpoint?.projectionSchemaVersion, envelope.projectionSchemaVersion)
        XCTAssertEqual(checkpoint?.entitySchemaVersion, envelope.entitySchemaVersion)
        XCTAssertEqual(checkpoint?.findingCount, 0)
        XCTAssertEqual(checkpoint?.eventCount, 1)
        XCTAssertEqual(checkpoint?.traceCount, 2)
    }

    func testCodeReviewSnapshotLoadsVerifiedFindingsEnvelopeFallback() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            verifiedFindings: nil,
            lastUpdatedAt: stableDate
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [:],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: []
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let loaded = MCPSharedState.readCodeReviewSnapshot(sessionId: "session-1")

        XCTAssertEqual(loaded?.verifiedFindings, envelope)
    }
}
