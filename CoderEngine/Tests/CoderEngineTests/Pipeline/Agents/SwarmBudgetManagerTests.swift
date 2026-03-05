import XCTest
@testable import CoderEngine

final class SwarmBudgetManagerTests: XCTestCase {

    private func makeTask(
        taskId: String = "T1",
        fileCount: Int = 3,
        risk: RiskLevel = .medium,
        taskType: TaskType = .feature
    ) -> TaskNode {
        TaskNode(
            taskId: taskId,
            title: "Test task",
            risk: risk,
            taskType: taskType,
            fileScope: (0..<fileCount).map { "file\($0).swift" }
        )
    }

    // MARK: - Capacity

    func testHasCapacityInitially() async {
        let mgr = SwarmBudgetManager()
        let task = makeTask()
        let has = await mgr.hasCapacity(task: task, role: .explorer)
        XCTAssertTrue(has)
    }

    func testCapacityExhaustedForRole() async {
        let config = SwarmBudgetConfig(
            maxExplorersPerTask: 1,
            maxTotalActiveAgents: 12
        )
        let mgr = SwarmBudgetManager(config: config)
        let task = makeTask()

        let r1 = await mgr.reserve(task: task, role: .explorer)
        XCTAssertTrue(r1)

        let has = await mgr.hasCapacity(task: task, role: .explorer)
        XCTAssertFalse(has)
    }

    func testGlobalCapacityLimit() async {
        let config = SwarmBudgetConfig(maxTotalActiveAgents: 2)
        let mgr = SwarmBudgetManager(config: config)

        let t1 = makeTask(taskId: "T1")
        let t2 = makeTask(taskId: "T2")
        let t3 = makeTask(taskId: "T3")

        _ = await mgr.reserve(task: t1, role: .explorer)
        _ = await mgr.reserve(task: t2, role: .coder)

        let has = await mgr.hasCapacity(task: t3, role: .explorer)
        XCTAssertFalse(has)
    }

    // MARK: - Reserve / Release

    func testReserveAndRelease() async {
        let mgr = SwarmBudgetManager()
        let task = makeTask()

        _ = await mgr.reserve(task: task, role: .explorer)
        var count = await mgr.currentTotalActive
        XCTAssertEqual(count, 1)

        await mgr.release(task: task, role: .explorer)
        count = await mgr.currentTotalActive
        XCTAssertEqual(count, 0)
    }

    func testReserveFailsWhenExhausted() async {
        let config = SwarmBudgetConfig(maxTotalActiveAgents: 1)
        let mgr = SwarmBudgetManager(config: config)

        let t1 = makeTask(taskId: "T1")
        let t2 = makeTask(taskId: "T2")

        let r1 = await mgr.reserve(task: t1, role: .explorer)
        XCTAssertTrue(r1)

        let r2 = await mgr.reserve(task: t2, role: .explorer)
        XCTAssertFalse(r2)

        let rejections = await mgr.totalRejections
        XCTAssertEqual(rejections, 1)
    }

    // MARK: - Adaptive Multiplier

    func testAdaptiveMultiplierHighComplexity() async {
        let mgr = SwarmBudgetManager()
        let task = makeTask(fileCount: 15, risk: .critical, taskType: .feature)
        let mult = await mgr.adaptiveMultiplier(for: task)
        XCTAssertGreaterThan(mult, 1.5)
        XCTAssertLessThanOrEqual(mult, 2.0)
    }

    func testAdaptiveMultiplierLowComplexity() async {
        let mgr = SwarmBudgetManager()
        let task = makeTask(fileCount: 1, risk: .low, taskType: .test)
        let mult = await mgr.adaptiveMultiplier(for: task)
        XCTAssertEqual(mult, 0.5, accuracy: 0.01)
    }

    func testAdaptiveDisabled() async {
        let config = SwarmBudgetConfig(
            maxExplorersPerTask: 3,
            adaptive: false
        )
        let mgr = SwarmBudgetManager(config: config)
        let task = makeTask(fileCount: 20, risk: .critical, taskType: .feature)

        let limit = await mgr.effectiveLimit(for: .explorer, task: task)
        XCTAssertEqual(limit, 3)
    }

    // MARK: - Provider Limit

    func testProviderLimit() async {
        let config = SwarmBudgetConfig(
            maxTotalActiveAgents: 10,
            maxAgentsPerProvider: 1
        )
        let mgr = SwarmBudgetManager(config: config)
        let task = makeTask()

        _ = await mgr.reserve(task: task, role: .explorer, providerId: "codex")
        let has = await mgr.hasCapacity(task: task, role: .coder, providerId: "codex")
        XCTAssertFalse(has)
    }

    // MARK: - Utilization

    func testUtilizationPercent() async {
        let config = SwarmBudgetConfig(maxTotalActiveAgents: 4)
        let mgr = SwarmBudgetManager(config: config)
        let task = makeTask()

        _ = await mgr.reserve(task: task, role: .explorer)
        _ = await mgr.reserve(task: task, role: .coder)

        let util = await mgr.utilizationPercent
        XCTAssertEqual(util, 50.0, accuracy: 0.1)
    }

    // MARK: - Reset

    func testReset() async {
        let mgr = SwarmBudgetManager()
        let task = makeTask()
        _ = await mgr.reserve(task: task, role: .explorer)

        await mgr.reset()
        let count = await mgr.currentTotalActive
        XCTAssertEqual(count, 0)
    }
}
