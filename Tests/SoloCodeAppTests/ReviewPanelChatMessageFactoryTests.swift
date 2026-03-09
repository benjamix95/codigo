import XCTest
import CoderEngine
@testable import CoderIDE

final class ReviewPanelChatMessageFactoryTests: XCTestCase {
    func testSummaryFactoryBuildsPrecomputedPresentation() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f-1",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/App/Main.swift",
                    message: "Something happened"
                )
            ],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/App/Main.swift"]),
            workspacePath: nil,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        let message = ReviewPanelChatMessageFactory.summary(snapshot: snapshot)

        XCTAssertEqual(message.kind, .summary)
        XCTAssertEqual(message.presentation?.sections.map(\.title), ["Outcome", "Findings"])
    }

    func testFindingUpdateFactoryBuildsDedicatedSection() {
        let message = ReviewPanelChatMessageFactory.findingUpdate(
            text: "Fix applied to finding f-1."
        )

        XCTAssertEqual(message.kind, .findingMutation)
        XCTAssertEqual(message.presentation?.sections.first?.title, "Finding Update")
        XCTAssertEqual(message.presentation?.sections.first?.lines, ["Fix applied to finding f-1."])
    }

    func testFindingUpdateFactoryBuildsStructuredPatchPreviewCard() {
        let finding = CodeReviewFinding(
            id: "f-structured",
            severity: .critical,
            category: .security,
            origin: .securityAuditor,
            filePath: "Sources/Auth/Guard.swift",
            lineNumber: 22,
            message: "Missing authorization guard on admin action.",
            suggestedFix: "Enforce role validation before executing the action.",
            confidence: 0.94,
            evidence: "Request reaches admin path without role check.",
            sourceTool: "security-auditor",
            status: .patchReady,
            verificationReport: "Verified by authz review and runtime trace."
        )
        let patch = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "f-structured",
            patchText: "patch-body",
            diffPreview: """
            --- a/Sources/Auth/Guard.swift
            +++ b/Sources/Auth/Guard.swift
            @@
            +guard currentUser.isAdmin else { throw AuthError.forbidden }
            """,
            touchedFiles: ["Sources/Auth/Guard.swift"],
            riskScore: 0.12,
            rollbackRef: "refs/rollback/patch-1",
            status: .verified,
            verifyStatus: .verified,
            validationStatus: .passed,
            validationSummary: "Regression checks passed."
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-structured",
            conversationId: nil,
            phase: .completed,
            stage: .findings,
            findings: [finding],
            patches: [patch],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: [finding.filePath]),
            workspacePath: nil,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        let message = ReviewPanelChatMessageFactory.findingUpdate(
            snapshot: snapshot,
            findingId: finding.id,
            title: "Patch pronta",
            detail: "Preview disponibile prima dell'apply."
        )

        XCTAssertEqual(message.kind, .findingMutation)
        XCTAssertEqual(
            message.presentation?.sections.map(\.title),
            ["Patch pronta", "Finding", "Verification", "Patch", "Patch Preview"]
        )
        XCTAssertTrue(message.content.contains("#### Patch Preview"))
        XCTAssertTrue(message.content.contains("rollback: available"))
    }
}
