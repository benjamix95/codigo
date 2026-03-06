import XCTest
@testable import CoderEngine

final class TaskRoleSelectionStrategyTests: XCTestCase {
    private let strategy = TaskRoleSelectionStrategy()

    func testStrategyUsesPreferredRoleWhenPresent() {
        let job = PipelineJob(
            jobId: "debug_job",
            workspace: "/tmp",
            request: "debug",
            jobKind: .debug,
            debugSession: DebugPipelineSessionContext(errorSummary: "Crash")
        )
        let task = TaskNode(
            taskId: "task_fix",
            title: "Apply fix",
            executionStyle: .singleAgent,
            preferredAgentRole: .testWriter,
            debugStage: .fix
        )

        XCTAssertEqual(strategy.nextRole(for: task, job: job), .testWriter)
    }

    func testStrategyUsesDebugStageDefaultsForDebugJobs() {
        let job = PipelineJob(
            jobId: "debug_job",
            workspace: "/tmp",
            request: "debug",
            jobKind: .debug,
            debugSession: DebugPipelineSessionContext(errorSummary: "Crash")
        )
        let task = TaskNode(
            taskId: "task_review",
            title: "Review fix",
            executionStyle: .singleAgent,
            debugStage: .reviewFix
        )

        XCTAssertEqual(strategy.nextRole(for: task, job: job), .reviewer)
    }

    func testStrategyPreservesLegacyStandardRouting() {
        let job = PipelineJob(
            jobId: "standard_job",
            workspace: "/tmp",
            request: "feature"
        )
        let pendingContextTask = TaskNode(
            taskId: "task_1",
            title: "Feature task"
        )
        let enrichedTask = TaskNode(
            taskId: "task_2",
            title: "Feature task",
            contextEnriched: true
        )

        XCTAssertEqual(strategy.nextRole(for: pendingContextTask, job: job), .explorer)
        XCTAssertEqual(strategy.nextRole(for: enrichedTask, job: job), .coder)
    }
}
