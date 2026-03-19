import XCTest
import MCP
@testable import CoderEngine
@testable import CoderIDEMCPServer

extension SecurityHandlerTests {
    func testSecurityStartUsesReviewStartWithSecurityPromptOverrideWhenGateReady() {
        let snapshot = makeSecurityGateReadySnapshot()
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_start",
            args: ["scope": "uncommitted"]
        )

        XCTAssertNotNil(result)
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("session_id"))
    }

    func testSecurityStartFailsWhenGateIsNotReady() {
        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_start",
            args: ["scope": "uncommitted"]
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("security gate not ready"))
    }

    func testSecurityStatusIncludesGateSummaryWithoutActiveSession() {
        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_status",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("security_gate_ready: false"))
        XCTAssertTrue(text.contains("security_gate_summary:"))
    }

    func testSecurityStartFailsClosedWhenRustCoreIsForcedOff() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let snapshot = makeSecurityGateReadySnapshot()
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_start",
            args: ["scope": "uncommitted"]
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("Rust review core unavailable for security_start"))
    }

    private func makeSecurityGateReadySnapshot() -> CodeReviewSessionSnapshot {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let finding = VerifiedFinding(
            id: "bug-gate-1",
            domain: .bug,
            title: "Crash fixed",
            summary: "Crash path verified and fixed",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .fixedVerified,
            filePath: "Sources/App.swift",
            evidenceIds: ["evidence-bug-gate-1"],
            verificationReportId: "verification-bug-gate-1",
            patchId: "patch-bug-gate-1",
            revalidationReportId: "revalidation-patch-bug-gate-1",
            reproducibility: .full,
            originEntryPoint: .mcp,
            findingFingerprint: "bug-gate-1",
            createdAt: now,
            updatedAt: now
        )
        let evidence = VerifiedEvidence(
            id: "evidence-bug-gate-1",
            findingId: "bug-gate-1",
            type: .testFailure,
            source: "Sources/App.swift",
            summary: "Crash reproduced in regression test",
            payloadRef: "inline:bug-gate-1",
            originTool: "xctest",
            originCommandId: "command-bug-gate-1",
            originRunId: "security-gate-baseline",
            originStep: "verify",
            sourceType: .test,
            capturedAt: now,
            artifactRef: "artifact:bug-gate-1",
            hashOrFingerprint: "hash-bug-gate-1",
            containsSensitiveData: false,
            redactionApplied: false,
            redactionReason: nil,
            retentionClass: .standard,
            visibilityLevel: .full,
            createdAt: now
        )
        let verification = VerifiedVerificationReport(
            id: "verification-bug-gate-1",
            findingId: "bug-gate-1",
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: ["reproduced with regression test"],
            commandLogRefs: ["command-bug-gate-1"],
            evidenceIds: ["evidence-bug-gate-1"],
            reasoningSummary: "verified",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: now
        )
        let patch = VerifiedPatchArtifact(
            id: "patch-bug-gate-1",
            findingId: "bug-gate-1",
            title: "Patch",
            strategy: .minimalFix,
            fileChanges: [
                VerifiedPatchFileChange(
                    filePath: "Sources/App.swift",
                    hunks: [VerifiedPatchHunk(startLineOld: 10, startLineNew: 10, diff: "@@", summary: "guard nil")]
                ),
            ],
            rationale: "minimal fix",
            regressionRisk: .low,
            linkedTestIds: ["test-bug-gate-1"],
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
            createdAt: now,
            updatedAt: now
        )
        let revalidation = VerifiedRevalidationReport(
            id: "revalidation-patch-bug-gate-1",
            findingId: "bug-gate-1",
            patchId: "patch-bug-gate-1",
            verdict: .fixedVerified,
            checksRun: ["test-bug-gate-1"],
            evidenceIds: ["evidence-bug-gate-1"],
            summary: "fixed",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: now
        )
        let run = VerifiedPipelineRun(
            id: "security-gate-baseline",
            status: .completed,
            domainScope: [.bug],
            workspaceId: "/tmp/repo",
            entryPoint: .mcp,
            budgetPolicy: VerifiedRunBudgetPolicy(),
            maxDuration: 600,
            maxToolCalls: 64,
            maxVerificationAttempts: 3,
            maxPatchAttempts: 2,
            maxRevalidationAttempts: 2,
            timeoutAt: nil,
            cancelledAt: nil,
            cancelReason: nil,
            toolCallCount: 3,
            verificationAttemptCount: 1,
            patchAttemptCount: 1,
            revalidationAttemptCount: 1,
            isCancellable: false,
            createdAt: now,
            updatedAt: now
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
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "security-gate-session",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            lastUpdatedAt: now
        )

        return CodeReviewSessionSnapshot(
            sessionId: "security-gate-session",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: now,
            completedAt: now,
            analysisCompletedAt: now,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            verifiedFindings: envelope,
            lastUpdatedAt: now
        )
    }
}

final class SecurityHandlerFailClosedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testSecurityStartFailsClosedWhenRustCoreIsForcedOff() {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "security-gate-session",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "bug-gate-1",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/App.swift",
                    message: "Crash fixed",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: now,
            completedAt: now,
            analysisCompletedAt: now,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: now
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_start",
            args: ["scope": "uncommitted"]
        )

        XCTAssertEqual(result?.isError, true)
        let text: String
        if let first = result?.content.first, case .text(let value) = first {
            text = value
        } else {
            text = ""
        }
        XCTAssertTrue(text.contains("Rust review core unavailable for security_start"))
    }
}
