import Foundation
import XCTest
@testable import CoderEngine

extension ProviderToolEventMapperTests {
    func testPlanCreateMapsToPlanLifecycleEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "plan_create",
            payload: [
                "goal": "Implementare plan panel",
                "steps": #"[{"step_id":"1","status":"pending"}]"#
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_create")
        XCTAssertEqual(mapped?.payload["goal"], "Implementare plan panel")
        XCTAssertEqual(mapped?.payload["tool"], "plan_create")
    }

    func testMCPCallPlanStepUpsertRemapsToPlanLifecycleEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_tool": "coderide_plan_step_upsert",
                "arguments": #"{"step_id":"2","status":"running","title":"Patch mapper"}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_step_upsert")
        XCTAssertEqual(mapped?.payload["step_id"], "2")
        XCTAssertEqual(mapped?.payload["status"], "running")
        XCTAssertEqual(mapped?.payload["title"], "Patch mapper")
    }

    func testMCPCallLegacyPlanStepUpdateRemainsCompatible() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_tool": "coderide_plan_step_update",
                "arguments": #"{"step_id":"3","status":"done","title":"Finalize"}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_step_update")
        XCTAssertEqual(mapped?.payload["step_id"], "3")
        XCTAssertEqual(mapped?.payload["status"], "done")
    }

    func testDirectLegacyPlanStepUpdateRemainsCompatible() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "plan_step_update",
            payload: [
                "step_id": "4",
                "status": "running",
                "title": "Compat"
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_step_update")
        XCTAssertEqual(mapped?.payload["step_id"], "4")
        XCTAssertEqual(mapped?.payload["status"], "running")
    }

    func testPlanDiffMapsSnapshotIdentifiers() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "plan_diff",
            payload: [
                "from_snapshot_id": "snap-1",
                "to_snapshot_id": "snap-2"
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_diff")
        XCTAssertEqual(mapped?.payload["from_snapshot_id"], "snap-1")
        XCTAssertEqual(mapped?.payload["to_snapshot_id"], "snap-2")
    }

    func testPlanLifecycleMapsCamelCaseAliases() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "plan_step_reorder",
            payload: [
                "conversationId": "11111111-1111-1111-1111-111111111111",
                "orderedStepIds": #"["2","1"]"#,
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_step_reorder")
        XCTAssertEqual(mapped?.payload["conversation_id"], "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(mapped?.payload["ordered_step_ids"], #"["2","1"]"#)
    }

    func testPlanDiffMapsCamelCaseSnapshotAliases() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "plan_diff",
            payload: [
                "fromSnapshotId": "snap-10",
                "toSnapshotId": "snap-11",
                "conversationId": "22222222-2222-2222-2222-222222222222",
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_diff")
        XCTAssertEqual(mapped?.payload["from_snapshot_id"], "snap-10")
        XCTAssertEqual(mapped?.payload["to_snapshot_id"], "snap-11")
        XCTAssertEqual(mapped?.payload["conversation_id"], "22222222-2222-2222-2222-222222222222")
    }

    func testPlanRequestUserInputMapsStructuredPayload() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_tool": "coderide_plan_request_user_input",
                "arguments": #"{\"title\":\"Clarify scope\",\"phase\":\"post-analysis\",\"questions\":[{\"prompt\":\"Target platform?\",\"options\":[{\"label\":\"iOS\",\"recommended\":true},{\"label\":\"macOS\"}]}]}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "plan_request_user_input")
        XCTAssertEqual(mapped?.payload["phase"], "post-analysis")
        XCTAssertEqual(mapped?.payload["tool"], "plan_request_user_input")
        XCTAssertNotNil(mapped?.payload["questions"])
    }
}
