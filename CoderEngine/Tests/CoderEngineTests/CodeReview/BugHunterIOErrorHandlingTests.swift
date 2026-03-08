import XCTest
@testable import CoderEngine

/// Tests that BugHunter I/O operations handle errors gracefully
/// (proper do/catch with logging) rather than silently swallowing
/// failures via `try?`.
///
/// Covers:
/// - MCPSharedState+BugHunter.swift (snapshot write/read)
/// - MCPSharedState+BugHunterCommands.swift (command enqueue/claim/mark)
/// - MCPSharedState+BugHunterHookEvents.swift (hook event enqueue/claim)
final class BugHunterIOErrorHandlingTests: XCTestCase {

    // MARK: - Snapshot Tests

    func testSnapshotWriteReadRoundtrip() {
        let snapshot = makeSnapshot(runId: "test-roundtrip-\(UUID().uuidString)")
        MCPSharedState.writeBugHunterSnapshot(snapshot)

        let loaded = MCPSharedState.readBugHunterSnapshot(runId: snapshot.runId)
        XCTAssertNotNil(loaded, "Snapshot should be readable after write")
        XCTAssertEqual(loaded?.runId, snapshot.runId)
        XCTAssertEqual(loaded?.status, .running)
        XCTAssertEqual(loaded?.sourceKind, .uncommitted)
        XCTAssertEqual(loaded?.gitRoot, "/tmp/test-repo")

        // Cleanup
        cleanupSnapshotFile(runId: snapshot.runId)
    }

    func testSnapshotReadNonExistent_returnsNil() {
        let result = MCPSharedState.readBugHunterSnapshot(runId: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(result, "Reading a non-existent snapshot should return nil, not crash")
    }

    func testSnapshotReadCorruptedData_returnsNil() {
        let runId = "corrupted-\(UUID().uuidString)"
        let filePath = MCPSharedState.bugHunterRunFilePath(runId: runId)
        MCPSharedState.ensureBugHunterDirectories()

        // Write invalid JSON data
        let corruptData = "{ invalid json }}}".data(using: .utf8)!
        try? corruptData.write(to: filePath, options: .atomic)

        let result = MCPSharedState.readBugHunterSnapshot(runId: runId)
        XCTAssertNil(result, "Corrupted snapshot should return nil gracefully")

        // Cleanup
        try? FileManager.default.removeItem(at: filePath)
    }

    func testSnapshotsRead_withConversationFilter() {
        let convId = UUID()
        let snap1 = makeSnapshot(
            runId: "conv-filter-1-\(UUID().uuidString)",
            conversationId: convId.uuidString.lowercased()
        )
        let snap2 = makeSnapshot(
            runId: "conv-filter-2-\(UUID().uuidString)",
            conversationId: UUID().uuidString.lowercased()
        )
        MCPSharedState.writeBugHunterSnapshot(snap1)
        MCPSharedState.writeBugHunterSnapshot(snap2)

        let filtered = MCPSharedState.readBugHunterSnapshots(conversationId: convId)
        XCTAssertTrue(
            filtered.contains(where: { $0.runId == snap1.runId }),
            "Should include snapshot matching conversationId"
        )
        XCTAssertFalse(
            filtered.contains(where: { $0.runId == snap2.runId }),
            "Should exclude snapshot with different conversationId"
        )

        // Cleanup
        cleanupSnapshotFile(runId: snap1.runId)
        cleanupSnapshotFile(runId: snap2.runId)
    }

    // MARK: - Command Tests

    func testCommandEnqueueAndClaim() {
        let convId = UUID()
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "test-action",
            runId: "cmd-test-\(UUID().uuidString)",
            conversationId: convId,
            payload: ["key": "value"]
        )
        XCTAssertEqual(command.status, .pending)
        XCTAssertEqual(command.action, "test-action")
        XCTAssertEqual(command.payload["key"], "value")

        let claimed = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertTrue(
            claimed.contains(where: { $0.id == command.id }),
            "Newly enqueued command should be claimable"
        )

        // After claiming, it should be processing — not claimable again
        let secondClaim = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertFalse(
            secondClaim.contains(where: { $0.id == command.id }),
            "Already claimed command should not be re-claimed"
        )

        // Cleanup: mark completed
        MCPSharedState.markBugHunterCommand(
            id: command.id, status: .completed, resultMessage: "done"
        )
    }

    func testCommandMarkStatus() {
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "mark-test",
            runId: "mark-\(UUID().uuidString)",
            conversationId: nil,
            payload: [:]
        )

        // Claim it first
        _ = MCPSharedState.claimPendingBugHunterCommands()

        // Mark as completed
        MCPSharedState.markBugHunterCommand(
            id: command.id, status: .completed, resultMessage: "success"
        )

        // It should no longer be claimable
        let claimed = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertFalse(
            claimed.contains(where: { $0.id == command.id }),
            "Completed command should not be claimable"
        )
    }

    func testCommandMarkNonExistentId_doesNotCrash() {
        // Should silently return without crash
        MCPSharedState.markBugHunterCommand(
            id: "nonexistent-\(UUID().uuidString)",
            status: .failed,
            resultMessage: "test"
        )
    }

    func testCommandHeartbeatRefresh() {
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "heartbeat-test",
            runId: "hb-\(UUID().uuidString)",
            conversationId: nil,
            payload: [:]
        )

        // Claim it
        _ = MCPSharedState.claimPendingBugHunterCommands()

        // Refresh heartbeat should not crash
        MCPSharedState.refreshBugHunterCommandHeartbeat(id: command.id)

        // Cleanup
        MCPSharedState.markBugHunterCommand(
            id: command.id, status: .completed, resultMessage: nil
        )
    }

    // MARK: - Hook Event Tests

    func testHookEventEnqueueAndClaim() {
        let gitRoot = "/tmp/hook-test-\(UUID().uuidString)"
        let sha = "abc123def456"

        MCPSharedState.enqueueBugHunterHookEvent(
            gitRoot: gitRoot, headSHA: sha
        )

        let events = MCPSharedState.claimBugHunterHookEvents()
        XCTAssertTrue(
            events.contains(where: { $0.gitRoot == gitRoot && $0.headSHA == sha }),
            "Enqueued hook event should be claimable"
        )

        // After claim, queue should be empty
        let secondClaim = MCPSharedState.claimBugHunterHookEvents()
        XCTAssertFalse(
            secondClaim.contains(where: { $0.gitRoot == gitRoot }),
            "Claimed events should be cleared from queue"
        )
    }

    func testHookEventDeduplication() {
        let gitRoot = "/tmp/dedup-test-\(UUID().uuidString)"
        let sha = "dedup123"

        // Enqueue the same event twice
        MCPSharedState.enqueueBugHunterHookEvent(gitRoot: gitRoot, headSHA: sha)
        MCPSharedState.enqueueBugHunterHookEvent(gitRoot: gitRoot, headSHA: sha)

        let events = MCPSharedState.claimBugHunterHookEvents()
        let matching = events.filter { $0.gitRoot == gitRoot && $0.headSHA == sha }
        XCTAssertEqual(matching.count, 1, "Duplicate hook events should be deduplicated")
    }

    func testHookEventEmptyInputIgnored() {
        // Empty gitRoot or SHA should be silently ignored
        MCPSharedState.enqueueBugHunterHookEvent(gitRoot: "", headSHA: "abc")
        MCPSharedState.enqueueBugHunterHookEvent(gitRoot: "/tmp", headSHA: "")
        MCPSharedState.enqueueBugHunterHookEvent(gitRoot: "  ", headSHA: "  ")

        let events = MCPSharedState.claimBugHunterHookEvents()
        let emptyMatches = events.filter {
            $0.gitRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.headSHA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        XCTAssertEqual(emptyMatches.count, 0, "Empty gitRoot/headSHA should not produce events")
    }

    // MARK: - Directory Creation Tests

    func testEnsureDirectoriesCreatesPath() {
        // This should not throw or crash even on repeated calls
        MCPSharedState.ensureBugHunterDirectories()
        MCPSharedState.ensureBugHunterDirectories()

        let exists = FileManager.default.fileExists(
            atPath: MCPSharedState.bugHunterSnapshotsDirectoryPath.path
        )
        XCTAssertTrue(exists, "BugHunter snapshots directory should exist after ensure")
    }

    // MARK: - Helpers

    private func makeSnapshot(
        runId: String,
        conversationId: String? = nil
    ) -> MCPSharedBugHunterSnapshot {
        MCPSharedBugHunterSnapshot(
            runId: runId,
            conversationId: conversationId,
            sourceKind: .uncommitted,
            triggerKind: .manual,
            gitRoot: "/tmp/test-repo",
            status: .running,
            lastUpdatedAt: Date()
        )
    }

    private func cleanupSnapshotFile(runId: String) {
        let path = MCPSharedState.bugHunterRunFilePath(runId: runId)
        try? FileManager.default.removeItem(at: path)
    }
}
