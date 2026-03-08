import XCTest
@testable import CoderEngine

final class MCPSharedBugHunterCommandsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try super.tearDownWithError()
    }

    func testEnqueueAndClaimBugHunterCommands() {
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: "run-1",
            conversationId: nil,
            payload: ["source_kind": "uncommitted"]
        )

        let claimed = MCPSharedState.claimPendingBugHunterCommands()

        XCTAssertEqual(claimed.count, 1)
        XCTAssertEqual(claimed.first?.id, command.id)
        XCTAssertEqual(claimed.first?.status, .processing)
    }

    func testSnapshotRoundTrip() {
        let snapshot = MCPSharedBugHunterSnapshot(
            runId: "run-1",
            reviewSessionId: "review-1",
            sourceKind: .commit,
            triggerKind: .manual,
            gitRoot: "/tmp/repo",
            branchName: "main",
            primaryCommit: "abc123",
            status: .running,
            startedAt: Date(),
            lastMessage: "running"
        )

        MCPSharedState.writeBugHunterSnapshot(snapshot)
        let loaded = MCPSharedState.readBugHunterSnapshot(runId: "run-1")

        XCTAssertEqual(loaded?.runId, snapshot.runId)
        XCTAssertEqual(loaded?.reviewSessionId, snapshot.reviewSessionId)
        XCTAssertEqual(loaded?.primaryCommit, snapshot.primaryCommit)
    }
}
