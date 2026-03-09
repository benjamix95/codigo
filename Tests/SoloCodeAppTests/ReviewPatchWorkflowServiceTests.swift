import XCTest
@testable import CoderIDE
@testable import CoderEngine

final class ReviewPatchWorkflowServiceTests: XCTestCase {
    func testApplyPatchRejectsArtifactThatWasNotVerified() {
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "preview",
            touchedFiles: ["File.swift"],
            status: .draft,
            verifyStatus: .pending
        )

        XCTAssertThrowsError(try service.applyPatch(artifact: artifact, workspaceRoot: "/tmp")) { error in
            XCTAssertEqual(error as? ReviewPatchWorkflowError, .patchNotVerified)
        }
    }
}
