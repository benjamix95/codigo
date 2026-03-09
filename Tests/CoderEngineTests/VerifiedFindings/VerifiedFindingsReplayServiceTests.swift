import XCTest
@testable import CoderEngine

final class VerifiedFindingsReplayServiceTests: XCTestCase {
    private let stableDate = Date(timeIntervalSince1970: 1_700_001_000)

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

    func testCheckpointServicePrefersStoredEnvelopeBeforeSyncFallback() {
        let envelope = makeEnvelope(sessionId: "replay-session")
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "replay-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: stableDate,
            completedAt: stableDate,
            analysisCompletedAt: stableDate,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            verifiedFindings: nil,
            lastUpdatedAt: stableDate
        )

        let recovered = VerifiedFindingsCheckpointService.resolveEnvelope(snapshot: snapshot)

        XCTAssertEqual(recovered.source, .storedEnvelope)
        XCTAssertEqual(recovered.envelope, envelope)
    }

    func testReplayServiceRebuildsProjectionFromCanonicalCheckpoint() throws {
        let envelope = makeEnvelope(sessionId: "replay-session")
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        try FileManager.default.removeItem(
            at: MCPSharedState.verifiedFindingsEnvelopeFilePath(sessionId: "replay-session")
        )

        let rebuilt = try XCTUnwrap(
            VerifiedFindingsCheckpointService.rebuildEnvelope(sessionId: "replay-session")
        )
        let report = VerifiedFindingsReplayService.replay(rebuilt)

        XCTAssertEqual(rebuilt.source, .rebuiltFromCanonical)
        XCTAssertEqual(report.sessionId, "replay-session")
        XCTAssertEqual(report.findingCount, 2)
        XCTAssertEqual(report.eventCount, 1)
        XCTAssertEqual(report.traceCount, 2)
        XCTAssertEqual(report.candidateCount, 1)
        XCTAssertEqual(report.verifiedCount, 1)
        XCTAssertEqual(report.duplicatesCount, 0)
    }

    private func makeEnvelope(sessionId: String) -> VerifiedFindingsSessionEnvelope {
        let candidate = VerifiedFinding(
            id: "candidate-1",
            domain: .bug,
            title: "Potential race",
            summary: "candidate",
            category: "concurrency",
            severity: .medium,
            confidence: 0.55,
            status: .candidate,
            filePath: "Sources/Race.swift",
            originEntryPoint: .reviewChat,
            findingFingerprint: "candidate-1",
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let verified = VerifiedFinding(
            id: "finding-1",
            domain: .bug,
            title: "Crash",
            summary: "verified",
            category: "correctness",
            severity: .high,
            confidence: 0.92,
            status: .verified,
            filePath: "Sources/App.swift",
            evidenceIds: ["evidence-1"],
            verificationReportId: "verification-1",
            originEntryPoint: .mcp,
            findingFingerprint: "finding-1",
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [candidate.id: candidate, verified.id: verified],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [
                VerifiedPipelineEvent(
                    id: "event-1",
                    runId: sessionId,
                    entityId: verified.id,
                    entityType: .finding,
                    eventType: "finding.verified",
                    payload: [:],
                    eventSchemaVersion: 1,
                    entitySchemaVersion: 1,
                    migrationHint: nil,
                    createdAt: stableDate
                ),
            ],
            traceLog: ["candidate", "verified"]
        )
        return VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            lastUpdatedAt: stableDate
        )
    }
}
