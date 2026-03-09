import XCTest
@testable import CoderEngine

final class VerifiedFindingAdmissionPolicyTests: XCTestCase {
    func testPromotionRequiresVerifiedReportAndEvidenceWithProvenance() {
        let finding = VerifiedFinding(
            domain: .bug,
            title: "Crash on nil unwrap",
            summary: "Runtime crash",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .candidate,
            filePath: "App.swift",
            originEntryPoint: .mainChat,
            findingFingerprint: "fp-1"
        )
        let report = VerifiedVerificationReport(
            id: "report-1",
            findingId: finding.id,
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: ["Run failing test"],
            commandLogRefs: ["cmd-1"],
            evidenceIds: ["evidence-1"],
            reasoningSummary: "Verified by failing test",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: Date()
        )
        let evidence = VerifiedEvidence(
            id: "evidence-1",
            findingId: finding.id,
            type: .testFailure,
            source: "unit-test",
            summary: "Assertion failed",
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

        XCTAssertTrue(
            VerifiedFindingAdmissionPolicy.canPromoteFinding(
                finding,
                verificationReports: [report],
                evidences: [evidence]
            )
        )
    }

    func testPromotionFailsWithoutEvidenceProvenance() {
        let finding = VerifiedFinding(
            domain: .bug,
            title: "Crash on nil unwrap",
            summary: "Runtime crash",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .candidate,
            filePath: "App.swift",
            originEntryPoint: .mainChat,
            findingFingerprint: "fp-1"
        )
        let report = VerifiedVerificationReport(
            id: "report-1",
            findingId: finding.id,
            verifierType: "test_runner",
            verdict: .verified,
            confidence: 0.95,
            steps: [],
            commandLogRefs: [],
            evidenceIds: [],
            reasoningSummary: "Verified",
            errorCategory: nil,
            failureReasonCode: nil,
            retryable: false,
            failurePhase: nil,
            retryCount: 0,
            maxRetryAllowed: 1,
            createdAt: Date()
        )
        let evidence = VerifiedEvidence(
            id: "evidence-1",
            findingId: finding.id,
            type: .testFailure,
            source: "unit-test",
            summary: "Assertion failed",
            payloadRef: "payload",
            originTool: "",
            originCommandId: "",
            originRunId: "",
            originStep: "",
            sourceType: .test,
            capturedAt: Date(),
            artifactRef: "artifact",
            hashOrFingerprint: "",
            containsSensitiveData: false,
            redactionApplied: false,
            redactionReason: nil,
            retentionClass: .standard,
            visibilityLevel: .full,
            createdAt: Date()
        )

        XCTAssertFalse(
            VerifiedFindingAdmissionPolicy.canPromoteFinding(
                finding,
                verificationReports: [report],
                evidences: [evidence]
            )
        )
    }
}
