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

    func testStatusPayloadIncludesPipelineProgressFields() {
        let finding = CodeReviewFinding(
            id: "finding-pipeline",
            severity: .warning,
            category: .security,
            origin: .securityAuditor,
            filePath: "Sources/Auth/Authz.swift",
            message: "Missing authorization guard",
            status: .patchReady,
            verificationReport: "Verified on the direct authorization path",
            verifiedAt: stableDate,
            patchArtifactId: "patch-pipeline"
        )
        let patch = ReviewPatchArtifact(
            id: "patch-pipeline",
            findingId: "finding-pipeline",
            patchText: "diff --git a/Authz.swift b/Authz.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/Auth/Authz.swift"],
            status: .verified,
            verifyStatus: .verified
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "pipeline-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [finding],
            patches: [patch],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/Auth/Authz.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: stableDate,
            completedAt: stableDate,
            analysisCompletedAt: stableDate,
            lastError: nil,
            currentJobId: "job-pipeline",
            lastTestStatus: .passed,
            audit: ReviewAuditSnapshot(
                toolCoverage: [
                    "standard": true,
                    "bugFinder": true,
                    "securityAudit": true,
                ],
                toolDurationsMs: [
                    "standard": 120,
                    "bugFinder": 90,
                    "securityAudit": 140,
                ],
                toolFindingsCounts: [
                    "standard": 0,
                    "bugFinder": 0,
                    "securityAudit": 1,
                ]
            ),
            lastUpdatedAt: stableDate
        )

        let payload = VerifiedFindingsStatusService.payload(snapshot: snapshot, entryPoint: .panel)

        XCTAssertEqual(payload["pipeline_phase"], "completed")
        XCTAssertEqual(payload["progress_percent"], "100")
        XCTAssertEqual(payload["steps_total"], "6")
        XCTAssertEqual(payload["steps_completed"], "6")
        XCTAssertEqual(payload["tools_total"], "3")
        XCTAssertEqual(payload["tools_completed"], "3")
        XCTAssertEqual(payload["verification_gate_ready"], "true")
        XCTAssertEqual(payload["patch_gate_ready"], "true")
        XCTAssertEqual(payload["publish_ready"], "true")
        XCTAssertEqual(payload["bundle_modes"], "standard,bugFinder,securityAudit")
    }
}
