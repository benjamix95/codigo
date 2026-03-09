import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ReviewPatchWorkflowServiceTests: XCTestCase {
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
}
