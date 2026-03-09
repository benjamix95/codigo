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
}
