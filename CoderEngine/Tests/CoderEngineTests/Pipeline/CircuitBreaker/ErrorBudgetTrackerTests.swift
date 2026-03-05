import XCTest
@testable import CoderEngine

final class ErrorBudgetTrackerTests: XCTestCase {

    private func makeTracker(
        maxPercent: Int = 30,
        maxConsecutive: Int = 5
    ) -> ErrorBudgetTracker {
        ErrorBudgetTracker(budget: ErrorBudget(
            maxFailedTasksPercent: maxPercent,
            maxConsecutiveFailures: maxConsecutive
        ))
    }

    // MARK: - Failure Weight

    func testFailureWeight_feature() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .feature, isCriticalPath: false),
            1
        )
    }

    func testFailureWeight_bugfix() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .bugfix, isCriticalPath: false),
            1
        )
    }

    func testFailureWeight_refactor() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .refactor, isCriticalPath: false),
            1
        )
    }

    func testFailureWeight_test_zero() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .test, isCriticalPath: false),
            0
        )
    }

    func testFailureWeight_docs_zero() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .docs, isCriticalPath: false),
            0
        )
    }

    func testFailureWeight_criticalPath_double() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .feature, isCriticalPath: true),
            2
        )
    }

    func testFailureWeight_criticalPath_overridesTestWeight() {
        let tracker = makeTracker()
        XCTAssertEqual(
            tracker.failureWeight(taskType: .test, isCriticalPath: true),
            2
        )
    }

    // MARK: - Failure Rate Calculation

    func testWeightedFailureRate_zero() {
        let tracker = makeTracker()
        let rate = tracker.weightedFailureRate(
            totalTasks: 0, weightedFailures: 0
        )
        XCTAssertEqual(rate, 0)
    }

    func testWeightedFailureRate_50percent() {
        let tracker = makeTracker()
        let rate = tracker.weightedFailureRate(
            totalTasks: 10, weightedFailures: 5
        )
        XCTAssertEqual(rate, 50.0, accuracy: 0.01)
    }

    func testWeightedFailureRate_100percent() {
        let tracker = makeTracker()
        let rate = tracker.weightedFailureRate(
            totalTasks: 5, weightedFailures: 5
        )
        XCTAssertEqual(rate, 100.0, accuracy: 0.01)
    }

    // MARK: - Budget Remaining

    func testBudgetRemaining_full() {
        let tracker = makeTracker(maxPercent: 30)
        let remaining = tracker.budgetRemaining(
            totalTasks: 10, weightedFailures: 0
        )
        XCTAssertEqual(remaining, 30.0, accuracy: 0.01)
    }

    func testBudgetRemaining_partial() {
        let tracker = makeTracker(maxPercent: 30)
        let remaining = tracker.budgetRemaining(
            totalTasks: 10, weightedFailures: 2
        )
        XCTAssertEqual(remaining, 10.0, accuracy: 0.01)
    }

    func testBudgetRemaining_exhausted() {
        let tracker = makeTracker(maxPercent: 30)
        let remaining = tracker.budgetRemaining(
            totalTasks: 10, weightedFailures: 4
        )
        XCTAssertLessThanOrEqual(remaining, 0)
    }

    // MARK: - Budget Low

    func testIsBudgetLow_true() {
        let tracker = makeTracker(maxPercent: 30)
        XCTAssertTrue(
            tracker.isBudgetLow(
                totalTasks: 100, weightedFailures: 25
            )
        )
    }

    func testIsBudgetLow_false_healthy() {
        let tracker = makeTracker(maxPercent: 30)
        XCTAssertFalse(
            tracker.isBudgetLow(
                totalTasks: 10, weightedFailures: 0
            )
        )
    }

    func testIsBudgetLow_false_exhausted() {
        let tracker = makeTracker(maxPercent: 30)
        XCTAssertFalse(
            tracker.isBudgetLow(
                totalTasks: 10, weightedFailures: 5
            )
        )
    }

    // MARK: - Budget Exhausted

    func testIsBudgetExhausted_true() {
        let tracker = makeTracker(maxPercent: 20)
        XCTAssertTrue(
            tracker.isBudgetExhausted(
                totalTasks: 10, weightedFailures: 2
            )
        )
    }

    func testIsBudgetExhausted_false() {
        let tracker = makeTracker(maxPercent: 30)
        XCTAssertFalse(
            tracker.isBudgetExhausted(
                totalTasks: 10, weightedFailures: 1
            )
        )
    }

    // MARK: - Consecutive Threshold

    func testConsecutiveThreshold_breached() {
        let tracker = makeTracker(maxConsecutive: 5)
        XCTAssertTrue(
            tracker.isConsecutiveThresholdBreached(
                consecutiveFailures: 5
            )
        )
    }

    func testConsecutiveThreshold_notBreached() {
        let tracker = makeTracker(maxConsecutive: 5)
        XCTAssertFalse(
            tracker.isConsecutiveThresholdBreached(
                consecutiveFailures: 4
            )
        )
    }

    // MARK: - Should Trip

    func testShouldTrip_lessThan5Tasks_false() {
        let tracker = makeTracker(maxConsecutive: 1)
        XCTAssertFalse(
            tracker.shouldTrip(
                totalTasks: 4,
                weightedFailures: 4,
                consecutiveFailures: 4
            )
        )
    }

    func testShouldTrip_budgetExhausted_true() {
        let tracker = makeTracker(maxPercent: 20)
        XCTAssertTrue(
            tracker.shouldTrip(
                totalTasks: 10,
                weightedFailures: 2,
                consecutiveFailures: 0
            )
        )
    }

    func testShouldTrip_consecutiveBreached_true() {
        let tracker = makeTracker(maxConsecutive: 3)
        XCTAssertTrue(
            tracker.shouldTrip(
                totalTasks: 10,
                weightedFailures: 0,
                consecutiveFailures: 3
            )
        )
    }

    func testShouldTrip_bothOk_false() {
        let tracker = makeTracker(
            maxPercent: 30, maxConsecutive: 5
        )
        XCTAssertFalse(
            tracker.shouldTrip(
                totalTasks: 10,
                weightedFailures: 1,
                consecutiveFailures: 2
            )
        )
    }

    // MARK: - Snapshot

    func testSnapshot_correct() {
        let tracker = makeTracker(maxPercent: 30, maxConsecutive: 5)
        let snap = tracker.snapshot(
            totalTasks: 100,
            weightedFailures: 25,
            consecutiveFailures: 1
        )

        XCTAssertEqual(snap.totalTasks, 100)
        XCTAssertEqual(snap.totalWeightedFailures, 25)
        XCTAssertEqual(snap.failureRatePercent, 25.0, accuracy: 0.01)
        XCTAssertEqual(snap.budgetMaxPercent, 30)
        XCTAssertEqual(snap.budgetRemainingPercent, 5.0, accuracy: 0.01)
        XCTAssertTrue(snap.isLow)
        XCTAssertFalse(snap.isExhausted)
        XCTAssertEqual(snap.consecutiveFailures, 1)
        XCTAssertEqual(snap.maxConsecutiveFailures, 5)
    }

    func testSnapshot_exhausted() {
        let tracker = makeTracker(maxPercent: 10)
        let snap = tracker.snapshot(
            totalTasks: 10,
            weightedFailures: 2,
            consecutiveFailures: 0
        )

        XCTAssertTrue(snap.isExhausted)
        XCTAssertFalse(snap.isLow)
    }

    // MARK: - Alert Check

    func testCheckAlert_nil_healthy() {
        let tracker = makeTracker(maxPercent: 50)
        let alert = tracker.checkAlert(
            totalTasks: 10, weightedFailures: 0
        )
        XCTAssertNil(alert)
    }

    func testCheckAlert_budgetLow() {
        let tracker = makeTracker(maxPercent: 30)
        let alert = tracker.checkAlert(
            totalTasks: 100, weightedFailures: 25
        )
        if case .budgetLow(let remaining) = alert {
            XCTAssertEqual(remaining, 5.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .budgetLow, got \(String(describing: alert))")
        }
    }

    func testCheckAlert_budgetExhausted() {
        let tracker = makeTracker(maxPercent: 20)
        let alert = tracker.checkAlert(
            totalTasks: 10, weightedFailures: 3
        )
        if case .budgetExhausted = alert {
        } else {
            XCTFail(
                "Expected .budgetExhausted, got \(String(describing: alert))"
            )
        }
    }

    // MARK: - Compute Weighted Failures

    func testComputeWeightedFailures_mixed() {
        let tracker = makeTracker()
        let records: [TaskFailureRecord] = [
            TaskFailureRecord(
                taskId: "t1", taskType: .feature,
                succeeded: false
            ),
            TaskFailureRecord(
                taskId: "t2", taskType: .test,
                succeeded: false
            ),
            TaskFailureRecord(
                taskId: "t3", taskType: .bugfix,
                isCriticalPath: true, succeeded: false
            ),
            TaskFailureRecord(
                taskId: "t4", taskType: .feature,
                succeeded: true
            ),
        ]

        let weight = tracker.computeWeightedFailures(from: records)
        XCTAssertEqual(weight, 3)
    }

    func testComputeWeightedFailures_allSuccess() {
        let tracker = makeTracker()
        let records: [TaskFailureRecord] = [
            TaskFailureRecord(
                taskId: "t1", succeeded: true
            ),
            TaskFailureRecord(
                taskId: "t2", succeeded: true
            ),
        ]
        XCTAssertEqual(
            tracker.computeWeightedFailures(from: records), 0
        )
    }

    // MARK: - Config Access

    func testConfigAccess() {
        let tracker = makeTracker(
            maxPercent: 25, maxConsecutive: 7
        )
        XCTAssertEqual(tracker.maxFailedTasksPercent, 25)
        XCTAssertEqual(tracker.maxConsecutiveFailures, 7)
    }
}
