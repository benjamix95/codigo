import XCTest
@testable import CoderEngine

final class VerifiedFindingsSessionSyncServiceTests: XCTestCase {
    func testSyncBuildsEnvelopeWithPatchAndRevalidationArtifacts() {
        let finding = CodeReviewFinding(
            id: "finding-1",
            severity: .critical,
            category: .correctness,
            origin: .bugHunter,
            filePath: "Sources/App.swift",
            lineNumber: 12,
            message: "Crash on nil access",
            confidence: 0.95,
            evidence: "token=secret-value",
            sourceTool: "xctest",
            status: .patchApplied,
            verificationReport: "Verified by failing regression test",
            verifiedAt: Date()
        )
        let patch = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "finding-1",
            patchText: "diff --git a/Sources/App.swift b/Sources/App.swift",
            diffPreview: "@@ -12,1 +12,2 @@",
            touchedFiles: ["Sources/App.swift"],
            riskScore: 0.2,
            rollbackRef: "reverse:patch-1",
            status: .applied,
            verifyStatus: .verified,
            validationRunId: "validation-1",
            validationStatus: .passed,
            validationSummary: "validation passed",
            applyMessage: "validation passed"
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [finding],
            candidates: [],
            patches: [patch],
            events: [.findingAdded(findingId: finding.id, severity: finding.severity.rawValue, filePath: finding.filePath)],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/App.swift"]),
            workspacePath: "/tmp/workspace",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            audit: .empty,
            outcome: .empty,
            lastUpdatedAt: Date()
        )

        let envelope = VerifiedFindingsSessionSyncService.sync(snapshot: snapshot, entryPoint: .mcp)

        XCTAssertEqual(envelope.sessionId, "session-1")
        XCTAssertEqual(envelope.canonicalSnapshot.findings.count, 1)
        XCTAssertEqual(envelope.canonicalSnapshot.patchArtifacts.count, 1)
        XCTAssertEqual(envelope.canonicalSnapshot.revalidationReports.count, 1)
        XCTAssertEqual(envelope.projectionSnapshot.verifiedQueue.count, 1)

        let evidence = envelope.canonicalSnapshot.evidences["evidence-finding-1"]
        XCTAssertEqual(evidence?.redactionApplied, true)
        XCTAssertEqual(evidence?.visibilityLevel, .redacted)
    }

    func testSyncMarksEquivalentCandidatesAsDuplicates() {
        let firstCandidate = ReviewCandidate(
            id: "candidate-1",
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Sources/App.swift",
            lineNumber: 30,
            message: "Potential nil access",
            evidence: "fatalError()",
            confidence: 0.82
        )
        let secondCandidate = ReviewCandidate(
            id: "candidate-2",
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Sources/App.swift",
            lineNumber: 31,
            message: "Potential nil access",
            evidence: "fatalError()",
            confidence: 0.81
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-duplicates",
            conversationId: nil,
            phase: .analyzing,
            stage: .analysis,
            findings: [],
            candidates: [firstCandidate, secondCandidate],
            patches: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/workspace",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            audit: .empty,
            outcome: .empty,
            lastUpdatedAt: Date()
        )

        let envelope = VerifiedFindingsSessionSyncService.sync(snapshot: snapshot, entryPoint: .reviewChat)

        XCTAssertEqual(envelope.projectionSnapshot.candidateQueue.count, 2)
        XCTAssertEqual(envelope.projectionSnapshot.duplicatesCount, 1)
        XCTAssertEqual(
            envelope.canonicalSnapshot.findings["candidate-2"]?.possibleDuplicateOf,
            ["candidate-1"]
        )
    }
}
