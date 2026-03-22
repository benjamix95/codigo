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
        setenv(
            "SOLOCODE_REVIEW_CORE_LIBRARY_PATH",
            reviewCoreLibraryPathForCodeReviewTests(from: #filePath),
            1
        )
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDownWithError() throws {
        if let backupPlanStateData {
            try? backupPlanStateData.write(to: planStateURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: planStateURL)
        }
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
    }

    func testStructuredMCPEditPayloadOmitsDiffPreview() {
        let structured = CoderIDEMCPServerApp.structuredMCPEditPayload(
            toolName: "coderide_str_replace",
            toolCallID: "tc-123",
            payload: [
                "path": "Sources/App.swift",
                "linesAdded": "1",
                "linesRemoved": "1",
                "diffPreview": "@@ -1 +1 @@\n-let a = 1\n+let a = 2",
            ],
            isError: false
        )

        XCTAssertEqual(structured["path"], "Sources/App.swift")
        XCTAssertEqual(structured["linesAdded"], "1")
        XCTAssertEqual(structured["linesRemoved"], "1")
        XCTAssertNil(structured["diffPreview"])
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

    func testPlanMutationsWithoutConversationIdFailWhenMultipleSnapshotsExist() {
        let conversationA = UUID().uuidString.lowercased()
        let conversationB = UUID().uuidString.lowercased()

        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationA,
                "goal": "Plan A",
                "steps": #"[{"step_id":"1","title":"A","status":"pending"}]"#,
            ]
        )
        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationB,
                "goal": "Plan B",
                "steps": #"[{"step_id":"1","title":"B","status":"pending"}]"#,
            ]
        )

        let update = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_update",
            args: [
                "step_id": "1",
                "status": "running",
                "title": "Ambiguous"
            ]
        )

        XCTAssertEqual(update.isError, true)
        XCTAssertTrue(extractText(from: update).contains("unable to resolve target plan snapshot"))
    }

    func testPlanMutationsWithoutConversationIdUseUniqueExistingSnapshot() throws {
        let conversationId = UUID().uuidString.lowercased()
        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Single plan context",
                "steps": #"[{"step_id":"1","title":"Audit","status":"pending"}]"#,
            ]
        )

        let update = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_update",
            args: [
                "step_id": "1",
                "status": "running",
                "title": "Audit"
            ]
        )
        XCTAssertNil(update.isError)

        let read = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_read",
            args: ["conversation_id": conversationId]
        )
        let json = extractText(from: read)
        let object = try XCTUnwrap(parseJSONObject(json))
        let snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        let steps = try XCTUnwrap(snapshot["steps"] as? [[String: Any]])
        let step = try XCTUnwrap(steps.first(where: { ($0["id"] as? String) == "1" }))
        XCTAssertEqual(step["status"] as? String, "running")
    }

    func testPlanStepBatchUpdateRejectsInvalidLinkedFilesShape() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_batch_update",
            args: [
                "updates": #"[{"step_id":"1","status":"running","linked_files":{"path":"Sources/A.swift"}}]"#
            ]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("invalid linked_files"))
    }

    func testPlanStepBatchUpdateRejectsInvalidDependsOnShape() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_batch_update",
            args: [
                "updates": #"[{"step_id":"1","status":"running","depends_on":[1,2]}]"#
            ]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("invalid depends_on"))
    }

    func testTodoWriteDoesNotFailOnIrrelevantInvalidConversationIdArgument() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "todo_write",
            args: [
                "title": "Aggiorna parser eventi",
                "status": "in_progress",
                "conversation_id": "not-a-uuid"
            ]
        )

        XCTAssertNil(result.isError)
        XCTAssertTrue(extractText(from: result).contains("todo list updated"))
    }

    func testTodoWriteAcceptsSingleJSONObjectStringForTodos() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "todo_write",
            args: [
                "todos": #"{"content":"Aggiorna parser eventi","status":"in_progress"}"#
            ]
        )

        XCTAssertNil(result.isError)
        XCTAssertTrue(extractText(from: result).contains("todo list updated"))
    }

    func testTodoWriteAcceptsChecklistStringForTodos() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "todo_write",
            args: [
                "todos": """
                - [ ] Analizzare i log
                - [~] Correggere il parser
                - [x] Verificare i test
                """
            ]
        )

        XCTAssertNil(result.isError)
        XCTAssertTrue(extractText(from: result).contains("todo list updated"))
    }

    func testPlanStepUpsertAcceptsCamelCaseAliases() throws {
        let conversationId = UUID().uuidString.lowercased()
        let upsert = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_upsert",
            args: [
                "conversationId": conversationId,
                "stepId": "7",
                "status": "running",
                "title": "Estrarre normalizer",
                "targetFile": "Sources/Normalizer.swift",
                "linkedFiles": #"["Sources/A.swift","Sources/B.swift"]"#,
                "dependsOn": #"["1","2"]"#,
            ]
        )
        XCTAssertNil(upsert.isError)

        let read = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_read",
            args: [
                "conversation_id": conversationId
            ]
        )
        XCTAssertNil(read.isError)
        let json = extractText(from: read)
        let object = try XCTUnwrap(parseJSONObject(json))
        let snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        let steps = try XCTUnwrap(snapshot["steps"] as? [[String: Any]])
        let step = try XCTUnwrap(steps.first(where: { ($0["id"] as? String) == "7" }))
        XCTAssertEqual(step["targetFile"] as? String, "Sources/Normalizer.swift")
        XCTAssertEqual(step["status"] as? String, "running")
        let linkedFiles = step["linkedFiles"] as? [String] ?? []
        XCTAssertEqual(Set(linkedFiles), Set(["Sources/A.swift", "Sources/B.swift"]))
        let dependsOn = step["dependsOn"] as? [String] ?? []
        XCTAssertEqual(Set(dependsOn), Set(["1", "2"]))
    }

    func testPlanCreateAcceptsCamelCaseOptions() throws {
        let conversationId = UUID().uuidString.lowercased()
        let create = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversationId": conversationId,
                "goal": "Hardening handlers",
                "steps": #"[{"step_id":"1","title":"Audit","status":"pending"}]"#,
                "chosenPath": "Path B",
                "replaceExisting": "true",
            ]
        )

        XCTAssertNil(create.isError)
        let read = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_read",
            args: [
                "conversationId": conversationId,
                "includeHistory": "true",
                "historyLimit": "2",
            ]
        )
        XCTAssertNil(read.isError)

        let json = extractText(from: read)
        let object = try XCTUnwrap(parseJSONObject(json))
        let snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["chosenPath"] as? String, "Path B")
        XCTAssertNotNil(object["history"] as? [[String: Any]])
    }

    func testPlanStepBatchUpdateAcceptsCamelCaseStepAndTargetFileAliases() throws {
        let conversationId = UUID().uuidString.lowercased()
        let create = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Alias batch update",
                "steps": #"[{"step_id":"1","title":"Base","status":"pending"}]"#,
            ]
        )
        XCTAssertNil(create.isError)

        let batch = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_batch_update",
            args: [
                "conversationId": conversationId,
                "updates": #"[{"stepId":"1","status":"running","targetFile":"Sources/New.swift","linkedFiles":["Sources/New.swift"],"dependsOn":["0"]}]"#,
            ]
        )
        XCTAssertNil(batch.isError)

        let read = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_read",
            args: ["conversation_id": conversationId]
        )
        let json = extractText(from: read)
        let object = try XCTUnwrap(parseJSONObject(json))
        let snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        let steps = try XCTUnwrap(snapshot["steps"] as? [[String: Any]])
        let step = try XCTUnwrap(steps.first(where: { ($0["id"] as? String) == "1" }))
        XCTAssertEqual(step["status"] as? String, "running")
        XCTAssertEqual(step["targetFile"] as? String, "Sources/New.swift")
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

    func testPlanStepUpsertRejectsInvalidStepIdentifierCharacters() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_step_upsert",
            args: [
                "conversation_id": UUID().uuidString.lowercased(),
                "step_id": "bad/id",
                "status": "running",
            ]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(extractText(from: result).contains("letters, numbers"))
    }

    func testPlanCreateMergeReportsZeroNewStepsWhenIdsAlreadyExist() {
        let conversationId = UUID().uuidString.lowercased()
        _ = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Merge base",
                "steps": #"[{"step_id":"1","title":"Audit","status":"pending"}]"#,
            ]
        )

        let merged = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_create",
            args: [
                "conversation_id": conversationId,
                "goal": "Merge base",
                "replace_existing": "false",
                "steps": #"[{"step_id":"1","title":"Audit","status":"pending"}]"#,
            ]
        )

        XCTAssertNil(merged.isError)
        XCTAssertTrue(extractText(from: merged).contains("0 new step(s) merged"))
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

    func testPlanDiffErrorMentionsRequestedSnapshotIdentifiers() {
        let result = CoderIDEMCPServerApp.handleIDEStateTool(
            name: "plan_diff",
            args: [
                "from_snapshot_id": "missing-from",
                "to_snapshot_id": "missing-to",
            ]
        )

        XCTAssertEqual(result.isError, true)
        let text = extractText(from: result)
        XCTAssertTrue(text.contains("missing-from"))
        XCTAssertTrue(text.contains("missing-to"))
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
