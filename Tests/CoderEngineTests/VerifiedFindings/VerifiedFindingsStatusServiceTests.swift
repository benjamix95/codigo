import XCTest
@testable import CoderEngine

final class VerifiedFindingsStatusServiceTests: XCTestCase {
    private let stableDate = Date(timeIntervalSince1970: 1_700_003_000)

    func testStatusPayloadIncludesProjectionReplayAndGateFields() {
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [
                "finding-1": VerifiedFinding(
                    id: "finding-1",
                    domain: .bug,
                    title: "Crash path",
                    summary: "bug",
                    category: "correctness",
                    severity: .high,
                    confidence: 0.95,
                    status: .fixedVerified,
                    filePath: "Sources/App.swift",
                    originEntryPoint: .mcp,
                    sourceOrigin: "bugHunter",
                    findingFingerprint: "finding-1",
                    createdAt: stableDate,
                    updatedAt: stableDate
                ),
            ],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "status-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: stableDate,
            completedAt: stableDate,
            analysisCompletedAt: stableDate,
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            verifiedFindings: VerifiedFindingsSessionEnvelope(
                sessionId: "status-session",
                canonicalSnapshot: canonical,
                projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
                lastUpdatedAt: stableDate
            ),
            lastUpdatedAt: stableDate
        )

        let payload = VerifiedFindingsStatusService.payload(snapshot: snapshot, entryPoint: .mcp)

        XCTAssertEqual(payload["verified_projection_findings"], "1")
        XCTAssertEqual(payload["verified_replay_findings"], "1")
        XCTAssertEqual(payload["verified_envelope_source"], "embedded_snapshot")
        XCTAssertEqual(payload["security_gate_ready"], "false")
        XCTAssertNotNil(payload["security_gate_summary"])
    }
}
