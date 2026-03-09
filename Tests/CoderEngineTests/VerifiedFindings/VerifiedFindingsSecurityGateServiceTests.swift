import XCTest
@testable import CoderEngine

final class VerifiedFindingsSecurityGateServiceTests: XCTestCase {
    func testGateReadyWhenProjectionMatchesAndBugFixesRevalidate() {
        let finding = VerifiedFinding(
            id: "finding-1",
            domain: .bug,
            title: "Crash",
            summary: "Crash",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .fixedVerified,
            filePath: "Sources/App.swift",
            evidenceIds: ["evidence-1"],
            verificationReportId: "verification-1",
            patchId: "patch-1",
            revalidationReportId: "revalidation-1",
            originEntryPoint: .mcp,
            findingFingerprint: "fp-1"
        )
        let evidence = VerifiedEvidence(
            id: "evidence-1",
            findingId: "finding-1",
            type: .testFailure,
            source: "unit",
            summary: "failed test",
            payloadRef: "payload",
            originTool: "xctest",
            originCommandId: "cmd-1",
            originRunId: "run-1",
            originStep: "verify",
            sourceType: .test,
            capturedAt: Date(),
            artifactRef: "artifact",
            hashOrFingerprint: "hash",
            containsSensitiveData: false,
            redactionApplied: false,
            redactionReason: nil,
            retentionClass: .standard,
            visibilityLevel: .full,
            createdAt: Date()
        )
        let verification = VerifiedVerificationReport(
            id: "verification-1",
            findingId: "finding-1",
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: ["run test"],
            commandLogRefs: [],
            evidenceIds: ["evidence-1"],
            reasoningSummary: "verified",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: Date()
        )
        let patch = VerifiedPatchArtifact(
            id: "patch-1",
            findingId: "finding-1",
            title: "Patch",
            strategy: .minimalFix,
            fileChanges: [],
            rationale: "fix",
            regressionRisk: .low,
            linkedTestIds: [],
            reversible: true,
            version: 1,
            workspaceId: "workspace",
            baseRevision: nil,
            targetRevision: nil,
            applyPreconditions: [],
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
            createdAt: Date(),
            updatedAt: Date()
        )
        let revalidation = VerifiedRevalidationReport(
            id: "revalidation-1",
            findingId: "finding-1",
            patchId: "patch-1",
            verdict: .fixedVerified,
            checksRun: ["validation-1"],
            evidenceIds: [],
            summary: "passed",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: Date()
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: ["finding-1": finding],
            evidences: ["evidence-1": evidence],
            verificationReports: ["verification-1": verification],
            patchArtifacts: ["patch-1": patch],
            revalidationReports: ["revalidation-1": revalidation],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical)
        )

        let report = VerifiedFindingsSecurityGateService.evaluate(envelope: envelope)
        XCTAssertTrue(report.ready)
        XCTAssertEqual(report.canonicalProjectionMismatchCount, 0)
        XCTAssertEqual(report.undetectedDuplicateCount, 0)
        XCTAssertEqual(report.findingsMissingEvidenceCount, 0)
        XCTAssertEqual(report.findingsMissingVerificationCount, 0)
        XCTAssertEqual(report.rollbackCoverageCount, 1)
        XCTAssertEqual(report.rollbackEligibleCount, 1)
    }

    func testGateBlockedWhenVerifiedFindingHasNoEvidence() {
        let finding = VerifiedFinding(
            id: "finding-1",
            domain: .bug,
            title: "Crash",
            summary: "Crash",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .verified,
            filePath: "Sources/App.swift",
            verificationReportId: "verification-1",
            originEntryPoint: .mcp,
            findingFingerprint: "fp-1"
        )
        let verification = VerifiedVerificationReport(
            id: "verification-1",
            findingId: "finding-1",
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: ["run test"],
            commandLogRefs: [],
            evidenceIds: [],
            reasoningSummary: "verified",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: Date()
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: ["finding-1": finding],
            evidences: [:],
            verificationReports: ["verification-1": verification],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical)
        )

        let report = VerifiedFindingsSecurityGateService.evaluate(envelope: envelope)
        XCTAssertFalse(report.ready)
        XCTAssertEqual(report.findingsMissingEvidenceCount, 1)
    }
}
