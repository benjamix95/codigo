import XCTest
@testable import CoderEngine

final class PipelineDebugGateStagesTests: XCTestCase {

    // MARK: - Gate Stages Present in Full Pipeline

    func testFullPipelineContainsGateStages() {
        let request = DebugSessionRequest(errorSummary: "Crash")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        XCTAssertTrue(tasks.contains { $0.debugStage == .awaitReproduceGate },
                       "Full pipeline should contain awaitReproduceGate")
        XCTAssertTrue(tasks.contains { $0.debugStage == .awaitFixGate },
                       "Full pipeline should contain awaitFixGate")
    }

    // MARK: - Gate Stage Order

    func testReproduceGateIsAfterRequestReproductionAndBeforeReproduce() throws {
        let request = DebugSessionRequest(errorSummary: "Crash")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        let requestIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .requestReproduction })
        let gateIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .awaitReproduceGate })
        let reproduceIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .reproduce })

        XCTAssertLessThan(requestIdx, gateIdx, "requestReproduction must come before awaitReproduceGate")
        XCTAssertLessThan(gateIdx, reproduceIdx, "awaitReproduceGate must come before reproduce")
    }

    func testFixGateIsAfterVerifyAndBeforeClean() throws {
        let request = DebugSessionRequest(
            errorSummary: "Bug",
            includeCleanupStage: true
        )
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        let verifyIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .verify })
        let gateIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .awaitFixGate })
        let cleanIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .clean })

        XCTAssertLessThan(verifyIdx, gateIdx, "verify must come before awaitFixGate")
        XCTAssertLessThan(gateIdx, cleanIdx, "awaitFixGate must come before clean")
    }

    // MARK: - Gate Stage Properties

    func testGateStagesHaveMCPToolExecutionStyle() {
        let request = DebugSessionRequest(errorSummary: "Crash")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        for task in tasks where task.debugStage == .awaitReproduceGate || task.debugStage == .awaitFixGate {
            XCTAssertEqual(task.executionStyle, .mcpTool,
                           "\(task.debugStage!) should use mcpTool execution style")
            XCTAssertEqual(task.metadata["user_gate"], "true",
                           "\(task.debugStage!) should have user_gate metadata")
        }
    }

    // MARK: - Gate Stage Timeouts

    func testGateStagesHaveLongTimeout() {
        XCTAssertEqual(
            PipelineJobFactory.timeoutForDebugStage(.awaitReproduceGate),
            600_000,
            "Reproduce gate should have 10 min timeout for user interaction"
        )
        XCTAssertEqual(
            PipelineJobFactory.timeoutForDebugStage(.awaitFixGate),
            600_000,
            "Fix gate should have 10 min timeout for user interaction"
        )
    }

    // MARK: - Gate Stages in Slices

    func testIntakeSliceContainsReproduceGate() {
        let request = DebugSessionRequest(errorSummary: "Crash")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider",
            slice: .intake
        )

        XCTAssertTrue(tasks.contains { $0.debugStage == .awaitReproduceGate },
                       "Intake slice should include awaitReproduceGate")
        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitFixGate },
                        "Intake slice should NOT include awaitFixGate")
    }

    func testInvestigationSliceContainsFixGate() {
        let request = DebugSessionRequest(errorSummary: "Bug")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider",
            slice: .investigation
        )

        XCTAssertTrue(tasks.contains { $0.debugStage == .awaitFixGate },
                       "Investigation slice should include awaitFixGate")
        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitReproduceGate },
                        "Investigation slice should NOT include awaitReproduceGate")
    }

    func testResolutionSliceDoesNotContainGates() {
        let request = DebugSessionRequest(errorSummary: "Resolved")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider",
            slice: .resolution
        )

        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitReproduceGate })
        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitFixGate })
    }

    // MARK: - Gate Stage Risk Levels

    func testGateStagesAreLowRisk() {
        XCTAssertEqual(PipelineJobFactory.riskForDebugStage(.awaitReproduceGate), .low)
        XCTAssertEqual(PipelineJobFactory.riskForDebugStage(.awaitFixGate), .low)
    }
}
