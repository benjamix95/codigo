import XCTest
@testable import CoderEngine

final class PipelineDebugJobFactoryTests: XCTestCase {
    func testFromDebugSessionBuildsDebugJobAndSequentialStages() throws {
        let request = DebugSessionRequest(
            errorSummary: "Crash on launch",
            workspaceHints: ["App/SoloCodeApp/Sources/Debug/DebugStore.swift"],
            targetPath: "/Applications/Codigo.app",
            arguments: ["--uitest"],
            backendPolicy: .appleHybrid,
            includeNativeStages: true
        )

        let (job, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: "/tmp/codigo",
            providerId: "codex-cli"
        )

        XCTAssertEqual(job.jobKind, .debug)
        XCTAssertEqual(job.selectedProviderProfile, "codex-cli")
        XCTAssertEqual(job.debugSession?.backendPolicy, .appleHybrid)
        XCTAssertEqual(job.debugSession?.errorSummary, "Crash on launch")
        XCTAssertEqual(tasks.first?.debugStage, .activateMode)
        XCTAssertEqual(tasks.last?.debugStage, .resolve)

        XCTAssertTrue(tasks.contains { $0.debugStage == .nativeStart })
        XCTAssertTrue(tasks.contains { $0.debugStage == .reviewFix })
        XCTAssertTrue(tasks.contains { $0.debugStage == .clean })

        for index in 1..<tasks.count {
            XCTAssertEqual(tasks[index].dependsOn, [tasks[index - 1].taskId])
        }

        let verifyTask = try XCTUnwrap(tasks.first { $0.debugStage == .verify })
        XCTAssertEqual(verifyTask.executionStyle, .singleAgent)
        XCTAssertEqual(verifyTask.preferredAgentRole, .testWriter)
        XCTAssertEqual(verifyTask.taskType, .test)
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
            workspace: "/tmp/codigo",
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
            targetPath: "/Applications/Codigo.app",
            arguments: ["--uitest"],
            breakpoints: breakpoints,
            watchExpressions: ["counter", "state.value"],
            backendPolicy: .appleHybrid,
            includeNativeStages: true
        )

        let (job, tasks) = PipelineJobFactory.fromDebugNativeStage(
            request,
            stage: .nativeSyncBreakpoints,
            workspace: "/tmp/codigo",
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
