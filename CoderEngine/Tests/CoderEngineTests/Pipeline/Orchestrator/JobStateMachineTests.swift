import XCTest
@testable import CoderEngine

final class JobStateMachineTests: XCTestCase {

    private func makeJob(state: JobState = .intake) -> PipelineJob {
        PipelineJob(
            jobId: "job_test_1",
            workspace: "/tmp/test",
            request: "Test request",
            state: state
        )
    }

    // MARK: - Valid Transitions

    func testValidTransitionIntakeToPlanning() async throws {
        let sm = JobStateMachine(job: makeJob())
        let record = try await sm.transition(to: .planning)
        XCTAssertEqual(record.from, .intake)
        XCTAssertEqual(record.to, .planning)
        let state = await sm.currentState
        XCTAssertEqual(state, .planning)
    }

    func testFullHappyPath() async throws {
        let sm = JobStateMachine(job: makeJob())
        try await sm.transition(to: .planning)
        try await sm.transition(to: .contextReady)
        try await sm.transition(to: .scheduled)
        try await sm.transition(to: .executing)
        try await sm.transition(to: .reviewing)
        try await sm.transition(to: .validating)
        try await sm.transition(to: .applying)
        try await sm.transition(to: .verifying)
        try await sm.transition(to: .finalized)

        let state = await sm.currentState
        XCTAssertEqual(state, .finalized)
        let terminal = await sm.isTerminal
        XCTAssertTrue(terminal)
    }

    // MARK: - Invalid Transitions

    func testInvalidTransitionThrows() async {
        let sm = JobStateMachine(job: makeJob())
        do {
            _ = try await sm.transition(to: .executing)
            XCTFail("Should have thrown")
        } catch {
            guard let smError = error as? JobStateMachineError,
                  case .invalidTransition(let from, let to) = smError else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            XCTAssertEqual(from, .intake)
            XCTAssertEqual(to, .executing)
        }
    }

    func testTerminalStateRejectsTransition() async throws {
        let sm = JobStateMachine(job: makeJob(state: .finalized))
        do {
            _ = try await sm.transition(to: .planning)
            XCTFail("Should have thrown")
        } catch let error as JobStateMachineError {
            if case .jobAlreadyTerminal(let state) = error {
                XCTAssertEqual(state, .finalized)
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    // MARK: - History

    func testTransitionHistoryRecorded() async throws {
        let sm = JobStateMachine(job: makeJob())
        try await sm.transition(to: .planning, reason: "Start planning")
        try await sm.transition(to: .contextReady)

        let history = await sm.history
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].from, .intake)
        XCTAssertEqual(history[0].to, .planning)
        XCTAssertEqual(history[0].reason, "Start planning")
        XCTAssertEqual(history[1].from, .planning)
        XCTAssertEqual(history[1].to, .contextReady)
    }

    // MARK: - Error/Recovery Path

    func testFailureToRetryPath() async throws {
        let sm = JobStateMachine(job: makeJob(state: .executing))
        try await sm.transition(to: .failed)
        try await sm.transition(to: .retrying)
        try await sm.transition(to: .scheduled)

        let state = await sm.currentState
        XCTAssertEqual(state, .scheduled)
    }

    func testRollingBackToScheduled() async throws {
        let sm = JobStateMachine(job: makeJob(state: .applying))
        try await sm.transition(to: .rollingBack)
        try await sm.transition(to: .scheduled)

        let state = await sm.currentState
        XCTAssertEqual(state, .scheduled)
    }

    func testCircuitBrokenToAborted() async throws {
        let sm = JobStateMachine(job: makeJob(state: .executing))
        try await sm.transition(to: .failed)
        try await sm.transition(to: .circuitBroken)
        try await sm.transition(to: .aborted)

        let state = await sm.currentState
        XCTAssertEqual(state, .aborted)
        let terminal = await sm.isTerminal
        XCTAssertTrue(terminal)
    }

    // MARK: - Rolling Back Timeout

    func testRollingBackTimeoutCheck() async throws {
        let sm = JobStateMachine(job: makeJob(state: .applying), rollingBackTimeoutMs: 1)
        try await sm.transition(to: .rollingBack)
        try await Task.sleep(nanoseconds: 5_000_000)
        do {
            try await sm.checkRollingBackTimeout()
            XCTFail("Should throw timeout")
        } catch let error as JobStateMachineError {
            if case .rollbackTimeout = error {
                // OK
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testNoTimeoutWhenNotRollingBack() async throws {
        let sm = JobStateMachine(job: makeJob(state: .executing))
        try await sm.checkRollingBackTimeout()
    }

    // MARK: - Abort

    func testAbortFromFailed() async throws {
        let sm = JobStateMachine(job: makeJob(state: .executing))
        try await sm.transition(to: .failed)
        try await sm.abort(reason: "Manual abort")
        let state = await sm.currentState
        XCTAssertEqual(state, .aborted)
    }

    // MARK: - Reset

    func testReset() async throws {
        let sm = JobStateMachine(job: makeJob())
        try await sm.transition(to: .planning)
        await sm.reset()
        let state = await sm.currentState
        XCTAssertEqual(state, .intake)
        let history = await sm.history
        XCTAssertTrue(history.isEmpty)
    }
}
