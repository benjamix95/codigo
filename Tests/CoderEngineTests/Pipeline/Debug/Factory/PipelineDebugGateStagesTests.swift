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

        let bootstrapIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .reproducePipelineBootstrap })
        let gateIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .awaitReproduceGate })
        let reproduceIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .reproduce })

        XCTAssertLessThan(bootstrapIdx, gateIdx, "reproducePipelineBootstrap must come before awaitReproduceGate")
        XCTAssertLessThan(gateIdx, reproduceIdx, "awaitReproduceGate must come before reproduce")
    }

    func testFixBootstrapIsAfterInstrumentAndBeforeFirstHypothesis() throws {
        let request = DebugSessionRequest(errorSummary: "Bug")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        let instrumentIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .instrument })
        let fixBootIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .fixPipelineBootstrap })
        let proposeHypothesisIdx = try XCTUnwrap(
            tasks.firstIndex { task in
                task.debugStage == .hypothesize && task.metadata["action"] == "propose"
            }
        )

        XCTAssertLessThan(instrumentIdx, fixBootIdx, "fixPipelineBootstrap must follow instrument")
        XCTAssertLessThan(fixBootIdx, proposeHypothesisIdx, "propose hypothesis must follow fix bootstrap")
    }

    func testFixGateWaitsForVerifyAndHypothesisUpdateBeforeClean() throws {
        let request = DebugSessionRequest(
            errorSummary: "Bug",
            includeCleanupStage: true
        )
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider"
        )

        let gateIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .awaitFixGate })
        let cleanIdx = try XCTUnwrap(tasks.firstIndex { $0.debugStage == .clean })
        let verifyTask = try XCTUnwrap(tasks.first { $0.debugStage == .verify })
        let hypothesisUpdateIdx = try XCTUnwrap(tasks.lastIndex { $0.debugStage == .hypothesize })
        let hypothesisUpdateTask = try XCTUnwrap(tasks.last { $0.debugStage == .hypothesize })

        XCTAssertLessThan(tasks.firstIndex { $0.taskId == verifyTask.taskId } ?? 0, gateIdx, "verify must come before awaitFixGate")
        XCTAssertLessThan(hypothesisUpdateIdx, gateIdx, "hypothesis update must come before awaitFixGate")
        XCTAssertLessThan(gateIdx, cleanIdx, "awaitFixGate must come before clean")
        let gateTask = try XCTUnwrap(tasks.first { $0.debugStage == .awaitFixGate })
        XCTAssertTrue(gateTask.dependsOn.contains(verifyTask.taskId) || gateTask.dependsOn.contains(hypothesisUpdateTask.taskId))
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
        XCTAssertTrue(tasks.contains { $0.debugStage == .fixPipelineBootstrap })
        XCTAssertFalse(tasks.contains { $0.debugStage == .setFixPhase })
        XCTAssertTrue(tasks.contains { $0.debugStage == .setVerifyPhase })
    }

    func testResolutionSliceContainsResolutionBackboneOnly() {
        let request = DebugSessionRequest(errorSummary: "Resolved")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/test",
            providerId: "test-provider",
            slice: .resolution
        )

        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitReproduceGate })
        XCTAssertFalse(tasks.contains { $0.debugStage == .awaitFixGate })
        XCTAssertTrue(tasks.contains { $0.debugStage == .timeline })
        XCTAssertTrue(tasks.contains { $0.debugStage == .sessionExport })
        XCTAssertTrue(tasks.contains { $0.debugStage == .sessionStop })
    }

    // MARK: - Gate Stage Risk Levels

    func testGateStagesAreLowRisk() {
        XCTAssertEqual(PipelineJobFactory.riskForDebugStage(.awaitReproduceGate), .low)
        XCTAssertEqual(PipelineJobFactory.riskForDebugStage(.awaitFixGate), .low)
    }
}
