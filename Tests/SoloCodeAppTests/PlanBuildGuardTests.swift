import XCTest
@testable import CoderIDE

final class PlanBuildGuardTests: XCTestCase {
    func testPlanBuildGuardActiveBeforeBuild() {
        XCTAssertTrue(
            isPlanBuildGuardActive(
                phase: .analyzing,
                planningState: .idle,
                coderMode: .plan,
                planToggleEnabled: false
            )
        )
        XCTAssertTrue(
            isPlanBuildGuardActive(
                phase: .readyToBuild,
                planningState: .awaitingChoice(planContent: "plan", options: []),
                coderMode: .agent,
                planToggleEnabled: true
            )
        )
        XCTAssertFalse(
            isPlanBuildGuardActive(
                phase: .building,
                planningState: .idle,
                coderMode: .plan,
                planToggleEnabled: false
            )
        )
    }

    func testPlanBuildGuardAllowsDiscoveryTools() {
        XCTAssertNil(
            planBuildGuardViolation(
                type: "mcp_tool_call",
                payload: ["mcp_tool": "read"]
            )
        )
        XCTAssertNil(
            planBuildGuardViolation(
                type: "mcp_tool_call",
                payload: ["mcp_tool": "subagent_explorer"]
            )
        )
        XCTAssertNil(
            planBuildGuardViolation(
                type: "command_execution",
                payload: ["command": "rg \"plan\" App"]
            )
        )
    }

    func testPlanBuildGuardBlocksMutatingOperations() {
        let toolViolation = planBuildGuardViolation(
            type: "mcp_tool_call",
            payload: ["mcp_tool": "write"]
        )
        XCTAssertEqual(toolViolation?.errorCode, "plan_build_required")

        let commandViolation = planBuildGuardViolation(
            type: "command_execution",
            payload: ["command": "touch /tmp/file.txt"]
        )
        XCTAssertEqual(commandViolation?.errorCode, "plan_build_required")
        XCTAssertTrue(commandViolation?.detail.contains("Press Build") ?? false)
    }
}
