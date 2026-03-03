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
        XCTAssertEqual(mapped?.payload["title"], "Plan step upsert")
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
}
