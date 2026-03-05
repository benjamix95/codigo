import XCTest
@testable import CoderEngine

final class PriorityCalculatorTests: XCTestCase {

    private let calc = PriorityCalculator()

    private func makeTask(
        priority: Int = 50,
        waitingSince: Date? = nil
    ) -> TaskNode {
        TaskNode(
            taskId: "T1",
            title: "Test task",
            priority: priority,
            waitingSince: waitingSince
        )
    }

    // MARK: - Effective Priority

    func testBaseOnlyPriorityNoWait() {
        let task = makeTask(priority: 70)
        let result = calc.effectivePriority(for: task)
        XCTAssertEqual(result, 70.0, accuracy: 0.001)
    }

    func testWaitTimeFactorAdded() {
        let now = Date()
        let waitingSince = now.addingTimeInterval(-30)
        let task = makeTask(priority: 50, waitingSince: waitingSince)

        let result = calc.effectivePriority(for: task, now: now)
        XCTAssertEqual(result, 50.0 + 3.0, accuracy: 0.1)
    }

    func testWaitTimeFactorZeroWithoutWaitingSince() {
        let task = makeTask(priority: 50)
        let factor = calc.waitTimeFactor(for: task)
        XCTAssertEqual(factor, 0.0)
    }

    func testWaitTimeFactorCalculation() {
        let now = Date()
        let waitingSince = now.addingTimeInterval(-100)
        let task = makeTask(waitingSince: waitingSince)

        let factor = calc.waitTimeFactor(for: task, now: now)
        XCTAssertEqual(factor, 10.0, accuracy: 0.1)
    }

    // MARK: - Sorting

    func testSortByPriorityDescending() {
        let t1 = TaskNode(taskId: "T1", title: "Low", priority: 30)
        let t2 = TaskNode(taskId: "T2", title: "High", priority: 90)
        let t3 = TaskNode(taskId: "T3", title: "Mid", priority: 60)

        let sorted = calc.sorted([t1, t2, t3])
        XCTAssertEqual(sorted.map(\.taskId), ["T2", "T3", "T1"])
    }

    func testSortTiebreakByTaskId() {
        let t1 = TaskNode(taskId: "A", title: "Same", priority: 50)
        let t2 = TaskNode(taskId: "B", title: "Same", priority: 50)
        let t3 = TaskNode(taskId: "C", title: "Same", priority: 50)

        let sorted = calc.sorted([t3, t1, t2])
        XCTAssertEqual(sorted.map(\.taskId), ["A", "B", "C"])
    }

    func testStarvationPreventionBoosted() {
        let now = Date()
        let lowPriWaiting = TaskNode(
            taskId: "T1", title: "Low priority waiting",
            priority: 20, waitingSince: now.addingTimeInterval(-600)
        )
        let highPriFresh = TaskNode(
            taskId: "T2", title: "High priority fresh",
            priority: 70
        )

        let sorted = calc.sorted([lowPriWaiting, highPriFresh], now: now)
        XCTAssertEqual(sorted.first?.taskId, "T1")
    }
}
