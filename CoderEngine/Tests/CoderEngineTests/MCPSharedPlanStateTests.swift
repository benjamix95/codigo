import Foundation
import XCTest
@testable import CoderEngine

final class MCPSharedPlanStateTests: XCTestCase {
    private var backupPlanStateData: Data?
    private var planStateURL: URL {
        MCPSharedState.planStateFilePath
    }

    override func setUpWithError() throws {
        backupPlanStateData = try? Data(contentsOf: planStateURL)
        try? FileManager.default.removeItem(at: planStateURL)
    }

    override func tearDownWithError() throws {
        if let backupPlanStateData {
            try? backupPlanStateData.write(to: planStateURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: planStateURL)
        }
    }

    func testWriteAndReadLatestSnapshot() throws {
        let conversationId = UUID()
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: "Goal A",
            chosenPath: "Option A",
            steps: [
                ["id": "1", "title": "Analyze", "status": "pending"]
            ]
        )

        let latest = try XCTUnwrap(
            MCPSharedState.readLatestPlanSnapshotJSONObject(conversationId: conversationId)
        )
        XCTAssertEqual(latest["conversation_id"] as? String, conversationId.uuidString.lowercased())
        let snapshot = try XCTUnwrap(latest["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["goal"] as? String, "Goal A")
        XCTAssertEqual((snapshot["steps"] as? [[String: Any]])?.count, 1)
    }

    func testHistoryRetentionIsCappedAtFiftySnapshots() {
        let conversationId = UUID()
        for idx in 0..<60 {
            MCPSharedState.writePlanSnapshotFromIDE(
                conversationId: conversationId,
                goal: "Goal \(idx)",
                chosenPath: nil,
                steps: [["id": "1", "title": "S\(idx)", "status": "pending"]],
                maxHistoryPerConversation: 50
            )
        }

        let history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: 100)
        XCTAssertEqual(history.count, 50)
    }

    func testDiffComputesAddedRemovedAndStatusChanges() throws {
        let conversationId = UUID()
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: "Goal Diff",
            chosenPath: nil,
            steps: [
                ["id": "1", "title": "Analyze", "status": "pending"],
                ["id": "2", "title": "Implement", "status": "pending"],
            ]
        )
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: "Goal Diff Updated",
            chosenPath: nil,
            steps: [
                ["id": "1", "title": "Analyze", "status": "done"],
                ["id": "3", "title": "Verify", "status": "pending"],
            ]
        )

        let history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: 2)
        let fromSnapshot = try XCTUnwrap(history.first?["snapshotId"] as? String)
        let toSnapshot = try XCTUnwrap(history.last?["snapshotId"] as? String)
        let diff = try XCTUnwrap(
            MCPSharedState.readPlanDiffJSONObject(
                conversationId: conversationId,
                fromSnapshotId: fromSnapshot,
                toSnapshotId: toSnapshot
            )
        )

        let added = try XCTUnwrap(diff["added_steps"] as? [[String: Any]])
        let removed = try XCTUnwrap(diff["removed_steps"] as? [[String: Any]])
        let statusChanges = try XCTUnwrap(diff["status_changes"] as? [[String: Any]])

        XCTAssertEqual(added.first?["id"] as? String, "3")
        XCTAssertEqual(removed.first?["id"] as? String, "2")
        XCTAssertEqual(statusChanges.first?["stepId"] as? String, "1")
        XCTAssertEqual(statusChanges.first?["fromStatus"] as? String, "pending")
        XCTAssertEqual(statusChanges.first?["toStatus"] as? String, "done")
        XCTAssertEqual(diff["goal_changed"] as? Bool, true)
    }

    func testReadWithoutConversationFallsBackToLatestConversation() throws {
        let firstConversation = UUID()
        let secondConversation = UUID()

        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: firstConversation,
            goal: "First goal",
            chosenPath: nil,
            steps: [["id": "1", "title": "First", "status": "pending"]]
        )
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: secondConversation,
            goal: "Second goal",
            chosenPath: nil,
            steps: [["id": "1", "title": "Second", "status": "pending"]]
        )

        let latest = try XCTUnwrap(MCPSharedState.readLatestPlanSnapshotJSONObject(conversationId: nil))
        XCTAssertEqual(latest["conversation_id"] as? String, secondConversation.uuidString.lowercased())
    }
}
