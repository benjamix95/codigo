import Foundation
import XCTest
import MCP
@testable import CoderEngine

#if canImport(CoderIDEMCPServer)
@testable import CoderIDEMCPServer

final class CoderIDEMCPServerPlanToolsTests: XCTestCase {
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

    func testPlanCreateRejectsMissingGoal() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: ["steps": "[]"]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("'goal'"))
    }

    func testPlanCreateThenReadReturnsSnapshotJSON() throws {
        let conversationId = UUID().uuidString.lowercased()
        let create = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Implementare Plan MCP v2",
                "steps": #"[{"step_id":"1","title":"Analisi","status":"pending"}]"#,
                "chosen_path": "Option A"
            ]
        )
        XCTAssertNil(create.isError)

        let read = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_read",
            args: [
                "conversation_id": conversationId,
                "include_history": "true",
                "history_limit": "5"
            ]
        )
        XCTAssertNil(read.isError)

        let json = extractText(from: read)
        let object = try XCTUnwrap(parseJSONObject(json))
        let snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["goal"] as? String, "Implementare Plan MCP v2")
        XCTAssertEqual(object["conversation_id"] as? String, conversationId)
        XCTAssertNotNil(object["history"] as? [[String: Any]])
    }

    func testPlanStepBatchUpdateRejectsInvalidStatus() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_batch_update",
            args: [
                "updates": #"[{"step_id":"1","status":"unknown"}]"#
            ]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("invalid status"))
    }

    func testPlanRequestUserInputRejectsInvalidQuestionsPayload() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_request_user_input",
            args: [
                "questions": "{\"prompt\":\"Missing array\"}"
            ]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("questions"))
    }

    func testPlanRequestUserInputAcceptsStructuredQuestionnaire() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_request_user_input",
            args: [
                "title": "Clarify deployment",
                "phase": "post-analysis",
                "round": "2",
                "questions": #"[{"prompt":"Target environment?","options":[{"label":"Production","recommended":true},{"label":"Staging"}]}]"#
            ]
        )

        XCTAssertNil(result.isError)
        XCTAssertTrue(extractText(from: result).contains("queued 1 clarification question"))
    }

    func testPlanDiffReturnsStatusChange() throws {
        let conversationId = UUID().uuidString.lowercased()
        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Goal A",
                "steps": #"[{"step_id":"1","title":"Analisi","status":"pending"}]"#
            ]
        )
        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_update",
            args: [
                "conversation_id": conversationId,
                "step_id": "1",
                "status": "done",
                "title": "Analisi"
            ]
        )

        let historyResult = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_history_read",
            args: [
                "conversation_id": conversationId,
                "limit": "2"
            ]
        )
        let historyJSON = extractText(from: historyResult)
        let history = try XCTUnwrap(parseJSONArray(historyJSON))
        XCTAssertEqual(history.count, 2)
        let fromSnapshotId = try XCTUnwrap(history.first?["snapshotId"] as? String)

        let diffResult = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_diff",
            args: [
                "conversation_id": conversationId,
                "from_snapshot_id": fromSnapshotId
            ]
        )

        XCTAssertNil(diffResult.isError)
        let diffJSON = extractText(from: diffResult)
        let diff = try XCTUnwrap(parseJSONObject(diffJSON))
        let statusChanges = try XCTUnwrap(diff["status_changes"] as? [[String: Any]])
        XCTAssertEqual(statusChanges.first?["stepId"] as? String, "1")
        XCTAssertEqual(statusChanges.first?["fromStatus"] as? String, "pending")
        XCTAssertEqual(statusChanges.first?["toStatus"] as? String, "done")
    }
}

private extension CoderIDEMCPServerPlanToolsTests {
    func extractText(from result: CallTool.Result) -> String {
        for item in result.content {
            if case .text(let text) = item {
                return text
            }
        }
        return ""
    }

    func parseJSONObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    func parseJSONArray(_ json: String) -> [[String: Any]]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return object
    }
}
#else
final class CoderIDEMCPServerPlanToolsTests: XCTestCase {
    func testCoderIDEMCPServerModuleUnavailableInCurrentBuild() throws {
        throw XCTSkip("CoderIDEMCPServer module is not importable in this xcodebuild configuration.")
    }
}
#endif
