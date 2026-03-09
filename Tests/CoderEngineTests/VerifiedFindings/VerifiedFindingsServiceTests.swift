import XCTest
@testable import CoderEngine

final class VerifiedFindingsServiceTests: XCTestCase {
    private let stableDate = Date(timeIntervalSince1970: 1_700_001_500)

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

    func testServiceResolvesStoredEnvelopeAndDerivedReports() {
        let envelope = makeEnvelope(sessionId: "service-session")
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "service-session",
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

        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: .mcp)

        XCTAssertEqual(resolved.recovered.source, .storedEnvelope)
        XCTAssertEqual(resolved.replayReport.findingCount, 1)
        XCTAssertEqual(resolved.securityGate.ready, true)
    }

    func testServiceResolvesFromSessionIdUsingCanonicalFallback() throws {
        let envelope = makeEnvelope(sessionId: "service-session")
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        try FileManager.default.removeItem(
            at: MCPSharedState.verifiedFindingsEnvelopeFilePath(sessionId: "service-session")
        )

        let resolved = try XCTUnwrap(
            VerifiedFindingsService.resolve(sessionId: "service-session", entryPoint: .mcp)
        )

        XCTAssertEqual(resolved.recovered.source, .rebuiltFromCanonical)
        XCTAssertEqual(resolved.replayReport.verifiedCount, 1)
    }

    private func makeEnvelope(sessionId: String) -> VerifiedFindingsSessionEnvelope {
        let finding = VerifiedFinding(
            id: "finding-1",
            domain: .bug,
            title: "Crash fixed",
            summary: "fixed",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .fixedVerified,
            filePath: "Sources/App.swift",
            evidenceIds: ["evidence-1"],
            verificationReportId: "verification-1",
            patchId: "patch-1",
            revalidationReportId: "revalidation-1",
            reproducibility: .full,
            originEntryPoint: .mcp,
            findingFingerprint: "finding-1",
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let evidence = VerifiedEvidence(
            id: "evidence-1",
            findingId: "finding-1",
            type: .testFailure,
            source: "Sources/App.swift",
            summary: "evidence",
            payloadRef: "inline:finding-1",
            originTool: "xctest",
            originCommandId: "command-1",
            originRunId: sessionId,
            originStep: "verify",
            sourceType: .test,
            capturedAt: stableDate,
            artifactRef: "artifact-1",
            hashOrFingerprint: "hash-1",
            containsSensitiveData: false,
            redactionApplied: false,
            redactionReason: nil,
            retentionClass: .standard,
            visibilityLevel: .full,
            createdAt: stableDate
        )
        let verification = VerifiedVerificationReport(
            id: "verification-1",
            findingId: "finding-1",
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: ["verified"],
            commandLogRefs: ["command-1"],
            evidenceIds: ["evidence-1"],
            reasoningSummary: "verified",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: stableDate
        )
        let patch = VerifiedPatchArtifact(
            id: "patch-1",
            findingId: "finding-1",
            title: "Patch",
            strategy: .minimalFix,
            fileChanges: [
                VerifiedPatchFileChange(
                    filePath: "Sources/App.swift",
                    hunks: [VerifiedPatchHunk(startLineOld: 10, startLineNew: 10, diff: "@@", summary: "guard")]
                ),
            ],
            rationale: "minimal fix",
            regressionRisk: .low,
            linkedTestIds: ["test-1"],
            reversible: true,
            version: 1,
            workspaceId: "/tmp/repo",
            baseRevision: "HEAD~1",
            targetRevision: "HEAD",
            applyPreconditions: ["Sources/App.swift"],
            rollbackAvailable: true,
            applyStrategy: "git_apply_3way",
            applyStatus: .applied,
            applyError: nil,
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            retryCount: 0,
            maxRetryAllowed: 1,
            containsSensitiveData: false,
            redactionApplied: false,
            retentionClass: .standard,
            visibilityLevel: .full,
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let revalidation = VerifiedRevalidationReport(
            id: "revalidation-1",
            findingId: "finding-1",
            patchId: "patch-1",
            verdict: .fixedVerified,
            checksRun: ["test-1"],
            evidenceIds: ["evidence-1"],
            summary: "fixed",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: stableDate
        )
        let run = VerifiedPipelineRun(
            id: sessionId,
            status: .completed,
            domainScope: [.bug],
            workspaceId: "/tmp/repo",
            entryPoint: .mcp,
            budgetPolicy: VerifiedRunBudgetPolicy(),
            maxDuration: 600,
            maxToolCalls: 8,
            maxVerificationAttempts: 2,
            maxPatchAttempts: 1,
            maxRevalidationAttempts: 1,
            timeoutAt: nil,
            cancelledAt: nil,
            cancelReason: nil,
            toolCallCount: 3,
            verificationAttemptCount: 1,
            patchAttemptCount: 1,
            revalidationAttemptCount: 1,
            isCancellable: false,
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [run.id: run],
            findings: [finding.id: finding],
            evidences: [evidence.id: evidence],
            verificationReports: [verification.id: verification],
            patchArtifacts: [patch.id: patch],
            revalidationReports: [revalidation.id: revalidation],
            commandLog: [],
            eventLog: [],
            traceLog: ["verified", "patched", "revalidated"]
        )
        return VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            lastUpdatedAt: stableDate
        )
    }
}
