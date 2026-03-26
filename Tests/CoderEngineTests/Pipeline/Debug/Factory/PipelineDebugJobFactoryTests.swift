import XCTest
@testable import CoderEngine

final class PipelineDebugJobFactoryTests: XCTestCase {
    func testFromDebugSessionBuildsDebugJobAndStructuredDagStages() throws {
        let request = DebugSessionRequest(
            errorSummary: "Crash on launch",
            workspaceHints: ["App/SoloCodeApp/Sources/Debug/DebugStore.swift"],
            targetPath: "/Applications/Solo Code.app",
            arguments: ["--uitest"],
            backendPolicy: .appleHybrid,
            includeNativeStages: true
        )

        let (job, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/solocode",
            providerId: "codex-cli"
        )

        XCTAssertEqual(job.jobKind, .debug)
        XCTAssertEqual(job.selectedProviderProfile, "codex-cli")
        XCTAssertEqual(job.debugSession?.backendPolicy, .appleHybrid)
        XCTAssertEqual(job.debugSession?.errorSummary, "Crash on launch")
        XCTAssertEqual(tasks.first?.debugStage, .describePipelineBootstrap)
        XCTAssertEqual(tasks.last?.debugStage, .sessionStop)

        XCTAssertTrue(tasks.contains { $0.debugStage == .nativeStart })
        XCTAssertTrue(tasks.contains { $0.debugStage == .reviewFix })
        XCTAssertTrue(tasks.contains { $0.debugStage == .clean })
        XCTAssertTrue(tasks.contains { $0.debugStage == .sessionStart })
        XCTAssertFalse(tasks.contains { $0.debugStage == .setDescribePhase })
        XCTAssertTrue(tasks.contains { $0.debugStage == .reproducePipelineBootstrap })
        XCTAssertTrue(tasks.contains { $0.debugStage == .fixPipelineBootstrap })
        XCTAssertFalse(tasks.contains { $0.debugStage == .setReproducePhase })
        XCTAssertFalse(tasks.contains { $0.debugStage == .requestReproduction })
        XCTAssertFalse(tasks.contains { $0.debugStage == .setFixPhase })
        XCTAssertTrue(tasks.contains { $0.debugStage == .requestClarification })
        XCTAssertTrue(tasks.contains { $0.debugStage == .snapshot })
        XCTAssertTrue(tasks.contains { $0.debugStage == .hypothesize })
        XCTAssertTrue(tasks.contains { $0.debugStage == .timeline })
        XCTAssertTrue(tasks.contains { $0.debugStage == .sessionExport })

        let verifyTask = try XCTUnwrap(tasks.first { $0.debugStage == .verify })
        XCTAssertEqual(verifyTask.executionStyle, .singleAgent)
        XCTAssertEqual(verifyTask.preferredAgentRole, .testWriter)
        XCTAssertEqual(verifyTask.taskType, .test)

        let reviewTask = try XCTUnwrap(tasks.first { $0.debugStage == .reviewFix })
        let setVerifyPhaseTask = try XCTUnwrap(tasks.first { $0.debugStage == .setVerifyPhase })
        XCTAssertEqual(Set(reviewTask.dependsOn), Set(setVerifyPhaseTask.dependsOn), "review and verify phase setup should branch from the same fix backbone")
        XCTAssertEqual(Set(verifyTask.dependsOn), Set([setVerifyPhaseTask.taskId]))

        let resolveTask = try XCTUnwrap(tasks.first { $0.debugStage == .resolve })
        let timelineTask = try XCTUnwrap(tasks.first { $0.debugStage == .timeline })
        let exportTask = try XCTUnwrap(tasks.first { $0.debugStage == .sessionExport })
        XCTAssertEqual(Set(resolveTask.dependsOn), Set([timelineTask.taskId, exportTask.taskId]))
    }

    func testDescribeClarificationsDependOnGatherContextOnlyForParallelism() throws {
        let request = DebugSessionRequest(errorSummary: "Parallel clarify")
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/solocode",
            providerId: "codex-cli"
        )
        let bootstrap = try XCTUnwrap(tasks.first { $0.debugStage == .describePipelineBootstrap })
        let sessionStart = try XCTUnwrap(tasks.first { $0.debugStage == .sessionStart })
        let gather = try XCTUnwrap(tasks.first { $0.debugStage == .gatherContext })
        XCTAssertEqual(Set(sessionStart.dependsOn), Set([bootstrap.taskId]))
        XCTAssertEqual(Set(gather.dependsOn), Set([sessionStart.taskId]))
        let clarifications = tasks.filter { $0.debugStage == .requestClarification }
        XCTAssertEqual(clarifications.count, 2)
        let firstClarify = try XCTUnwrap(clarifications.first { $0.metadata["question_index"] == "1" })
        let secondClarify = try XCTUnwrap(clarifications.first { $0.metadata["question_index"] == "2" })
        XCTAssertEqual(Set(firstClarify.dependsOn), Set([gather.taskId]))
        XCTAssertEqual(Set(secondClarify.dependsOn), Set([firstClarify.taskId]))
        let analyze = try XCTUnwrap(tasks.first { $0.debugStage == .analyzeIssue })
        XCTAssertEqual(
            Set(analyze.dependsOn),
            Set(clarifications.map(\.taskId))
        )
    }

    func testNativeSyncWatchesRunAfterBreakpoints() throws {
        let request = DebugSessionRequest(
            errorSummary: "Native sync order",
            watchExpressions: ["x", "y"],
            includeNativeStages: true
        )
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/solocode",
            providerId: "codex-cli"
        )
        let start = try XCTUnwrap(tasks.first { $0.debugStage == .nativeStart })
        let bp = try XCTUnwrap(tasks.first { $0.debugStage == .nativeSyncBreakpoints })
        let watches = try XCTUnwrap(tasks.first { $0.debugStage == .nativeSyncWatches })
        XCTAssertEqual(Set(bp.dependsOn), Set([start.taskId]))
        XCTAssertEqual(Set(watches.dependsOn), Set([bp.taskId]))
        let repro = try XCTUnwrap(tasks.first { $0.debugStage == .reproduce })
        XCTAssertEqual(Set(repro.dependsOn), Set([bp.taskId, watches.taskId]))
    }

    func testInvestigationSliceInsertsHostReproduceAckBeforeNativeStart() throws {
        let request = DebugSessionRequest(
            errorSummary: "Continue inv",
            includeNativeStages: true
        )
        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/solocode",
            providerId: "codex-cli",
            slice: .investigation
        )
        let ack = try XCTUnwrap(tasks.first { $0.debugStage == .hostReproduceGateAck })
        XCTAssertEqual(
            ack.metadata[PipelineHostCheckpoint.metadataKey],
            PipelineHostCheckpoint.hostReproduceAck.rawValue
        )
        let start = try XCTUnwrap(tasks.first { $0.debugStage == .nativeStart })
        XCTAssertEqual(Set(start.dependsOn), Set([ack.taskId]))
    }

    func testFromDebugSessionOmitsOptionalStagesWhenDisabled() {
        let request = DebugSessionRequest(
            errorSummary: "Regression",
            includeReviewStage: false,
            includeCleanupStage: false,
            includeNativeStages: false
        )

        let (_, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/solocode",
            providerId: "codex-cli"
        )

        XCTAssertFalse(tasks.contains { $0.debugStage == .reviewFix })
        XCTAssertFalse(tasks.contains { $0.debugStage == .clean })
        XCTAssertFalse(tasks.contains { $0.debugStage == .nativeStart })
        XCTAssertFalse(tasks.contains { $0.debugStage == .nativeStop })
    }

    func testFromDebugNativeStageSerializesBreakpointsAndWatches() throws {
        let breakpoints = [
            DebugNativeBreakpointSpec(
                id: "bp-1",
                filePath: "Sources/App.swift",
                line: 42,
                condition: "counter > 0",
                isActive: true
            ),
        ]
        let request = DebugSessionRequest(
            errorSummary: "Native sync",
            workspaceHints: ["Sources/App.swift"],
            targetPath: "/Applications/Solo Code.app",
            arguments: ["--uitest"],
            breakpoints: breakpoints,
            watchExpressions: ["counter", "state.value"],
            backendPolicy: .appleHybrid,
            includeNativeStages: true
        )

        let (job, tasks) = PipelineJobFactory.fromDebugNativeStage(
            request,
            stage: .nativeSyncBreakpoints,
            workspace: "/tmp/solocode",
            providerId: "codex-cli"
        )

        XCTAssertEqual(job.jobKind, .debug)
        XCTAssertEqual(job.debugSession?.backendPolicy, .appleHybrid)

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.executionStyle, .nativeCommand)
        XCTAssertEqual(task.debugStage, .nativeSyncBreakpoints)
        XCTAssertEqual(task.metadata["watch_expressions"], "counter\nstate.value")

        let breakpointsJSON = try XCTUnwrap(task.metadata["native_breakpoints_json"])
        let decoded = try JSONDecoder().decode(
            [DebugNativeBreakpointSpec].self,
            from: Data(breakpointsJSON.utf8)
        )
        XCTAssertEqual(decoded, breakpoints)
    }
}
