import XCTest
@testable import CoderEngine

// MARK: - Mock Delegate

private final class MockCBDelegate: CircuitBreakerDelegate, @unchecked Sendable {
    var tripEvents: [(String, Double, Int, Double)] = []
    var recoverEvents: [String] = []
    var budgetLowEvents: [(String, Double)] = []

    func onCircuitBreakerTripped(
        jobId: String,
        failureRate: Double,
        consecutiveFailures: Int,
        budgetRemaining: Double
    ) async {
        tripEvents.append(
            (jobId, failureRate, consecutiveFailures, budgetRemaining)
        )
    }

    func onCircuitBreakerRecovered(jobId: String) async {
        recoverEvents.append(jobId)
    }

    func onErrorBudgetLow(
        jobId: String,
        remaining: Double
    ) async {
        budgetLowEvents.append((jobId, remaining))
    }
}

// MARK: - Tests

final class CircuitBreakerTests: XCTestCase {

    private func makeCB(
        maxFailedPercent: Int = 30,
        maxConsecutive: Int = 5,
        cooldownMs: Int = 30_000,
        delegate: CircuitBreakerDelegate? = nil
    ) -> CircuitBreaker {
        CircuitBreaker(
            jobId: "test_job",
            budget: ErrorBudget(
                maxFailedTasksPercent: maxFailedPercent,
                maxConsecutiveFailures: maxConsecutive
            ),
            cooldownMs: cooldownMs,
            delegate: delegate
        )
    }

    // MARK: - Initial State

    func testInitialState_closed() async {
        let cb = makeCB()
        let phase = await cb.phase
        XCTAssertEqual(phase, .closed)
        let canDispatch = await cb.canDispatch
        XCTAssertTrue(canDispatch)
    }

    func testInitialState_disabled_lessThan5Tasks() async {
        let cb = makeCB()
        let disabled = await cb.isDisabled
        XCTAssertTrue(disabled)
    }

    // MARK: - Record Success

    func testRecordSuccess_keepsClosed() async {
        let cb = makeCB()
        let transition = await cb.recordSuccess()
        XCTAssertEqual(transition, .noChange)
        let phase = await cb.phase
        XCTAssertEqual(phase, .closed)
    }

    func testRecordSuccess_resetsConsecutiveFailures() async {
        let cb = makeCB()
        _ = await cb.recordFailure()
        _ = await cb.recordFailure()
        _ = await cb.recordSuccess()
        let state = await cb.state
        XCTAssertEqual(state.consecutiveFailures, 0)
    }

    // MARK: - Record Failure — No Trip (< 5 tasks)

    func testRecordFailure_lessThan5Tasks_noTrip() async {
        let cb = makeCB(maxConsecutive: 2)
        _ = await cb.recordFailure()
        _ = await cb.recordFailure()
        _ = await cb.recordFailure()
        let phase = await cb.phase
        XCTAssertEqual(phase, .closed)
    }

    // MARK: - Trip on Consecutive Failures

    func testTrip_consecutiveFailures() async {
        let delegate = MockCBDelegate()
        let cb = makeCB(
            maxFailedPercent: 80,
            maxConsecutive: 3,
            delegate: delegate
        )

        for _ in 0..<7 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure()
        _ = await cb.recordFailure()
        let t = await cb.recordFailure()

        let phase = await cb.phase
        XCTAssertEqual(phase, .open)

        if case .tripped = t {
        } else {
            XCTFail("Expected .tripped transition, got \(t)")
        }

        XCTAssertEqual(delegate.tripEvents.count, 1)
    }

    // MARK: - Trip on Failure Rate

    func testTrip_failureRateExceedsBudget() async {
        let delegate = MockCBDelegate()
        let cb = makeCB(
            maxFailedPercent: 20,
            maxConsecutive: 100,
            delegate: delegate
        )

        for _ in 0..<4 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure()
        _ = await cb.recordFailure()

        let phase = await cb.phase
        XCTAssertEqual(phase, .open)
        XCTAssertEqual(delegate.tripEvents.count, 1)
    }

    // MARK: - Cooldown and Half-Open

    func testCooldown_transitionsToHalfOpen() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 100)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        let phaseBefore = await cb.phase
        XCTAssertEqual(phaseBefore, .open)

        try? await Task.sleep(nanoseconds: 150_000_000)

        let transition = await cb.checkCooldown()
        XCTAssertEqual(transition, .cooldownExpired)

        let phaseAfter = await cb.phase
        XCTAssertEqual(phaseAfter, .halfOpen)
    }

    func testCooldown_notExpiredYet() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 60_000)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        let transition = await cb.checkCooldown()
        XCTAssertEqual(transition, .noChange)

        let remaining = await cb.remainingCooldownMs()
        XCTAssertGreaterThan(remaining, 0)
    }

    // MARK: - Half-Open Probe Success

    func testHalfOpen_probeSuccess_closesCB() async {
        let delegate = MockCBDelegate()
        let cb = makeCB(
            maxConsecutive: 1,
            cooldownMs: 100,
            delegate: delegate
        )

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        try? await Task.sleep(nanoseconds: 150_000_000)
        _ = await cb.checkCooldown()

        let transition = await cb.recordSuccess()
        XCTAssertEqual(transition, .probeSucceeded)

        let phase = await cb.phase
        XCTAssertEqual(phase, .closed)
        XCTAssertEqual(delegate.recoverEvents.count, 1)
    }

    // MARK: - Half-Open Probe Failure

    func testHalfOpen_probeFailure_reopensWithDoubledCooldown() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 100)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        try? await Task.sleep(nanoseconds: 150_000_000)
        _ = await cb.checkCooldown()

        let transition = await cb.recordFailure()
        if case .probeFailed(let newCooldown) = transition {
            XCTAssertEqual(newCooldown, 200)
        } else {
            XCTFail("Expected .probeFailed, got \(transition)")
        }

        let phase = await cb.phase
        XCTAssertEqual(phase, .open)
    }

    // MARK: - Max Cooldown Cap

    func testCooldown_cappedAtMax() async {
        let state = CircuitBreakerState(
            jobId: "test",
            state: .halfOpen,
            totalTasks: 10,
            cooldownMs: 200_000,
            probesSinceHalfOpen: 0
        )
        let cb = CircuitBreaker(
            state: state,
            budget: ErrorBudget(
                maxFailedTasksPercent: 30,
                maxConsecutiveFailures: 5
            )
        )

        _ = await cb.recordFailure()
        let newState = await cb.state
        XCTAssertEqual(newState.cooldownMs, CircuitBreaker.maxCooldownMs)
    }

    // MARK: - Abort After 3 Probe Failures

    func testShouldAbortJob_after3ProbeFailures() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 10)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure()
        let phaseAfterTrip = await cb.phase
        XCTAssertEqual(phaseAfterTrip, .open)

        let cooldowns = [20, 30, 50]
        for sleepMs in cooldowns {
            try? await Task.sleep(
                nanoseconds: UInt64(sleepMs) * 1_000_000
            )
            _ = await cb.checkCooldown()
            _ = await cb.recordFailure()
        }

        let shouldAbort = await cb.shouldAbortJob
        XCTAssertTrue(shouldAbort)
    }

    // MARK: - Task Type Weights

    func testFailure_testTask_doesNotCountInBudget() async {
        let cb = makeCB(maxFailedPercent: 10, maxConsecutive: 100)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure(taskType: .test)
        _ = await cb.recordFailure(taskType: .test)
        _ = await cb.recordFailure(taskType: .test)

        let phase = await cb.phase
        XCTAssertEqual(phase, .closed)

        let state = await cb.state
        XCTAssertEqual(state.totalFailures, 0)
    }

    func testFailure_docsTask_doesNotCountInBudget() async {
        let cb = makeCB(maxFailedPercent: 10, maxConsecutive: 100)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure(taskType: .docs)

        let state = await cb.state
        XCTAssertEqual(state.totalFailures, 0)
    }

    func testFailure_criticalPath_countsDouble() async {
        let delegate = MockCBDelegate()
        let cb = makeCB(
            maxFailedPercent: 20,
            maxConsecutive: 100,
            delegate: delegate
        )

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }

        _ = await cb.recordFailure(isCriticalPath: true)

        let state = await cb.state
        XCTAssertEqual(state.totalFailures, 2)
    }

    // MARK: - Error Budget Low

    func testErrorBudgetLow_emitsWarning() async {
        let delegate = MockCBDelegate()
        let cb = makeCB(
            maxFailedPercent: 30,
            maxConsecutive: 100,
            delegate: delegate
        )

        for _ in 0..<3 {
            _ = await cb.recordSuccess()
        }
        for _ in 0..<2 {
            _ = await cb.recordFailure()
        }

        let remaining = await cb.errorBudgetRemaining
        let isLow = await cb.isErrorBudgetLow
        XCTAssertLessThan(remaining, 10)
        XCTAssertTrue(isLow)
    }

    // MARK: - canDispatch / canDispatchProbe

    func testCanDispatch_open_false() async {
        let cb = makeCB(maxConsecutive: 1)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        let canDispatch = await cb.canDispatch
        XCTAssertFalse(canDispatch)

        let canProbe = await cb.canDispatchProbe
        XCTAssertFalse(canProbe)
    }

    func testCanDispatchProbe_halfOpen_true() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 50)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        try? await Task.sleep(nanoseconds: 60_000_000)
        _ = await cb.checkCooldown()

        let canProbe = await cb.canDispatchProbe
        XCTAssertTrue(canProbe)

        let canDispatch = await cb.canDispatch
        XCTAssertFalse(canDispatch)
    }

    // MARK: - Stats

    func testStats_tracked() async {
        let cb = makeCB(maxConsecutive: 1, cooldownMs: 50)

        for _ in 0..<5 {
            _ = await cb.recordSuccess()
        }
        _ = await cb.recordFailure()

        try? await Task.sleep(nanoseconds: 60_000_000)
        _ = await cb.checkCooldown()

        _ = await cb.recordSuccess()

        let stats = await cb.stats
        XCTAssertEqual(stats.trips, 1)
        XCTAssertEqual(stats.recoveries, 1)
    }

    // MARK: - Init From Persisted State

    func testInitFromPersistedState() async {
        let state = CircuitBreakerState(
            jobId: "job_persisted",
            state: .open,
            consecutiveFailures: 3,
            totalFailures: 5,
            totalTasks: 10,
            failureRatePercent: 50,
            trippedAt: Date(),
            cooldownMs: 60_000
        )
        let cb = CircuitBreaker(
            state: state,
            budget: ErrorBudget()
        )

        let phase = await cb.phase
        XCTAssertEqual(phase, .open)
        let isOpen = await cb.isOpen
        XCTAssertTrue(isOpen)
    }
}
