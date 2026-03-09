import XCTest
@testable import CoderEngine

final class BugHunterWorkflowServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testQueueLifecycleCommandRoutesApplyThroughSharedLifecycle() throws {
        let patch = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "f123",
            patchText: "diff --git a/Package.swift b/Package.swift",
            diffPreview: "@@",
            touchedFiles: ["Package.swift"],
            status: .applied,
            verifyStatus: .verified,
            validationStatus: .passed
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f123",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Package.swift",
                    message: "Test finding",
                    verificationReport: "verified",
                    verifiedAt: Date(),
                    patchArtifactId: "patch-1"
                )
            ],
            patches: [patch],
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
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let queued = try BugHunterWorkflowService.queueLifecycleCommand(
            action: "apply_patch",
            sessionId: "review-session",
            findingId: "f123",
            conversationId: nil,
            payload: [
                "session_id": "review-session",
                "finding_id": "f123",
            ]
        )

        XCTAssertEqual(queued.findingId, "f123")
        XCTAssertEqual(queued.patchId, "patch-1")
        XCTAssertEqual(queued.patchVerifyStatus, "verified")
    }
}
