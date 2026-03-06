import XCTest
@testable import CoderIDE

final class SwarmProgressMetricsTests: XCTestCase {
    func testMetricsUseCompletedAndRunningStepsForProgressLabel() {
        let metrics = SwarmProgressMetrics(
            steps: [
                SwarmStep(name: "Planner", status: .completed),
                SwarmStep(name: "Coder", status: .inProgress),
                SwarmStep(name: "Reviewer", status: .pending),
            ],
            pipelineSnapshot: nil
        )

        XCTAssertEqual(metrics.totalSteps, 3)
        XCTAssertEqual(metrics.completedSteps, 1)
        XCTAssertEqual(metrics.runningSteps, 1)
        XCTAssertEqual(metrics.pendingSteps, 1)
        XCTAssertEqual(metrics.progressLabel, "2/3 steps")
        XCTAssertEqual(metrics.summaryLabel, "1 done • 1 running • 1 pending")
    }

    func testMetricsFallbackToPipelineSnapshotWhenNamedStepsAreNotAvailableYet() {
        let snapshot = PipelineConversationSnapshot(
            currentJobId: "job-1",
            providerId: "provider-1",
            assistantMessageId: UUID(),
            planConversationId: nil,
            jobState: .executing,
            completedTasks: 2,
            totalTasks: 5,
            isRunning: true,
            lastError: nil,
            circuitBreakerActive: false,
            jobStartTime: Date()
        )

        let metrics = SwarmProgressMetrics(
            steps: [],
            pipelineSnapshot: snapshot
        )

        XCTAssertEqual(metrics.totalSteps, 5)
        XCTAssertEqual(metrics.completedSteps, 2)
        XCTAssertEqual(metrics.runningSteps, 1)
        XCTAssertEqual(metrics.pendingSteps, 2)
        XCTAssertEqual(metrics.progressLabel, "3/5 steps")
        XCTAssertEqual(metrics.summaryLabel, "2 done • 1 running • 2 pending")
    }

    func testInternalSingleTaskPhaseHidesStepCount() {
        let snapshot = PipelineConversationSnapshot(
            currentJobId: "chat-1",
            providerId: "provider-chat",
            assistantMessageId: UUID(),
            planConversationId: nil,
            jobState: .executing,
            completedTasks: 0,
            totalTasks: 1,
            isRunning: true,
            lastError: nil,
            circuitBreakerActive: false,
            jobStartTime: Date()
        )

        let metrics = SwarmProgressMetrics(
            steps: [],
            pipelineSnapshot: snapshot
        )

        XCTAssertTrue(metrics.isInternalSingleTaskPhase)
        XCTAssertEqual(metrics.progressLabel, "Running…")
    }
}
