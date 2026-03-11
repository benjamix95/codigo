import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodigoAppCodeReviewCommandLoopCloseFindingTests: XCTestCase {
    private var workspaceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codigo-review-close-finding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        workspaceURL = nil
        try super.tearDownWithError()
    }

    func testCloseFindingCommandUsesRustMutationForValidatedPatchAppliedFinding() async throws {
        let app = CodigoApp()
        let patch = ReviewPatchArtifact(
            id: "patch-close-1",
            findingId: "finding-close-1",
            patchText: "diff --git a/Sources/File.swift b/Sources/File.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/File.swift"],
            status: .applied,
            verifyStatus: .verified,
            validationStatus: .passed
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "close-finding-session",
            conversationId: nil,
            phase: .fixing,
            stage: .fixing,
            findings: [
                CodeReviewFinding(
                    id: "finding-close-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Close me after validated apply",
                    status: .patchApplied
                )
            ],
            patches: [patch],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/File.swift"]),
            workspacePath: workspaceURL.path,
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-close-1",
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "close_finding",
            sessionId: snapshot.sessionId,
            conversationId: nil,
            payload: [
                "session_id": snapshot.sessionId,
                "finding_id": "finding-close-1",
                "reason": "fixed_verified",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let commands = try decoder.decode(
            [MCPSharedCodeReviewCommand].self,
            from: try Data(contentsOf: MCPSharedState.codeReviewCommandsFilePath)
        )
        XCTAssertEqual(commands.first(where: { $0.id == command.id })?.status, .completed)
        let updated = try XCTUnwrap(MCPSharedState.readCodeReviewSnapshot(sessionId: snapshot.sessionId))
        XCTAssertEqual(updated.findings.first?.status, .closed)
    }
}
