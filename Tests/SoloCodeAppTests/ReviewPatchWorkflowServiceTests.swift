import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ReviewPatchWorkflowServiceTests: XCTestCase {
    func testPreparePatchPromptIncludesVerificationRemediationAndInvariantContext() {
        let service = ReviewPatchWorkflowService()
        let finding = CodeReviewFinding(
            id: "finding-ctx",
            severity: .warning,
            category: .correctness,
            filePath: "Sources/File.swift",
            lineNumber: 42,
            message: "Invariant broken",
            suggestedFix: "Ripristina il guard sullo stato",
            expectedInvariant: "Lo stato finale deve essere emesso una sola volta",
            reproOrReasoning: "Il retry duplica l'evento terminale",
            verificationReport: "Riproduzione confermata con retry consecutivo",
            verifiedAt: Date()
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-ctx",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [finding],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        let prompt = service.preparePatchPrompt(finding: finding, snapshot: snapshot)

        XCTAssertTrue(prompt.contains("Verifica: Riproduzione confermata con retry consecutivo"))
        XCTAssertTrue(prompt.contains("Fix suggerito: Ripristina il guard sullo stato"))
        XCTAssertTrue(prompt.contains("Invariante atteso: Lo stato finale deve essere emesso una sola volta"))
        XCTAssertTrue(prompt.contains("Repro o reasoning: Il retry duplica l'evento terminale"))
    }

    func testApplyPatchRejectsArtifactThatWasNotVerified() async {
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "preview",
            touchedFiles: ["File.swift"],
            status: .draft,
            verifyStatus: .pending
        )

        do {
            _ = try await service.applyPatch(artifact: artifact, workspaceRoot: "/tmp")
            XCTFail("Expected patchNotVerified")
        } catch {
            XCTAssertEqual(error as? ReviewPatchWorkflowError, .patchNotVerified)
        }
    }

    func testUpsertingPatchUpdatesFindingStatusAndPatchReference() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue"
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )
        let artifact = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["Sources/File.swift"],
            status: .applied,
            verifyStatus: .verified
        )

        let updated = VerifiedFindingsPatchExecutionService.upsertingPatch(
            in: snapshot,
            artifact: artifact
        )

        XCTAssertEqual(updated.patches.first?.id, "patch-1")
        XCTAssertEqual(updated.findings.first?.patchArtifactId, "patch-1")
        XCTAssertEqual(updated.findings.first?.status, .patchApplied)
    }

    func testCloseFindingExecutionClosesMergedFinding() async throws {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        let updated = try await VerifiedFindingsPatchExecutionService.execute(
            action: "close_finding",
            snapshot: snapshot,
            findingId: "finding-close",
            workspaceRoot: "/tmp/repo",
            preferredProviderId: nil,
            providerRegistry: ProviderRegistry()
        )

        XCTAssertEqual(updated.findings.first?.status, .closed)
        XCTAssertEqual(updated.events.last?.type, .outcomePublished)
    }
}
