import XCTest
import MCP
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testReviewRevalidateFindingQueuesCommand() {
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
        let snapshot = seedSnapshot(
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
            ]
        ).copying(patches: [patch])
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_revalidate_finding",
            args: reviewSessionArgs(snapshot, extras: ["finding_id": "f123"])
        )
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("queued"))
    }

    func testReviewRollbackPatchQueuesCommand() {
        let patch = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "f123",
            patchText: "diff --git a/Package.swift b/Package.swift",
            diffPreview: "@@",
            touchedFiles: ["Package.swift"],
            rollbackRef: "reverse:patch-1",
            status: .applied,
            verifyStatus: .verified,
            validationStatus: .passed
        )
        let snapshot = seedSnapshot(
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
            ]
        ).copying(patches: [patch])
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_rollback_patch",
            args: reviewSessionArgs(snapshot, extras: ["finding_id": "f123"])
        )
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("queued"))
    }
}
