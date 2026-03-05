import XCTest
@testable import CoderEngine

final class TaskCompletionHandlerTests: XCTestCase {

    private let handler = TaskCompletionHandler()

    private func makeTask(taskId: String = "T1", taskType: TaskType = .feature) -> TaskNode {
        TaskNode(
            taskId: taskId,
            title: "Test task",
            taskType: taskType,
            fileScope: ["a.swift"]
        )
    }

    private func makeResult(
        taskId: String = "T1",
        role: AgentRole = .coder,
        success: Bool = true,
        error: String? = nil
    ) -> WorkerTaskResult {
        WorkerTaskResult(
            taskId: taskId,
            agentName: "Test-\(role.rawValue)",
            agentRole: role,
            success: success,
            error: error
        )
    }

    // MARK: - Success Routing

    func testExplorerSuccessSchedulesCoder() {
        let result = makeResult(role: .explorer)
        let task = makeTask()
        let action = handler.handleSuccess(result: result, task: task)
        XCTAssertEqual(action, .scheduleNextAgent(taskId: "T1", role: .coder))
    }

    func testCoderSuccessSchedulesReviewer() {
        let result = makeResult(role: .coder)
        let task = makeTask()
        let action = handler.handleSuccess(result: result, task: task)
        XCTAssertEqual(action, .scheduleNextAgent(taskId: "T1", role: .reviewer))
    }

    func testDebuggerSuccessSchedulesReviewer() {
        let result = makeResult(role: .debugger)
        let task = makeTask()
        let action = handler.handleSuccess(result: result, task: task)
        XCTAssertEqual(action, .scheduleNextAgent(taskId: "T1", role: .reviewer))
    }

    func testReviewerSuccessNoFindingsSchedulesTestWriter() {
        let result = makeResult(role: .reviewer)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task, hasCriticalFindings: false
        )
        XCTAssertEqual(action, .scheduleNextAgent(taskId: "T1", role: .testWriter))
    }

    func testReviewerWithCriticalFindingsSchedulesFix() {
        let result = makeResult(role: .reviewer)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task, hasCriticalFindings: true
        )
        if case .scheduleFixRound(let tid, _) = action {
            XCTAssertEqual(tid, "T1")
        } else {
            XCTFail("Expected scheduleFixRound, got \(action)")
        }
    }

    func testTestWriterPassTransitionsToValidation() {
        let result = makeResult(role: .testWriter)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task, testsPass: true
        )
        XCTAssertEqual(action, .transitionToValidation(taskId: "T1"))
    }

    func testTestWriterPassWithDocWriter() {
        let result = makeResult(role: .testWriter)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task,
            testsPass: true, shouldInvokeDocWriter: true
        )
        XCTAssertEqual(action, .scheduleNextAgent(taskId: "T1", role: .docWriter))
    }

    func testTestWriterFailSchedulesFix() {
        let result = makeResult(role: .testWriter)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task, testsPass: false
        )
        if case .scheduleFixRound(let tid, _) = action {
            XCTAssertEqual(tid, "T1")
        } else {
            XCTFail("Expected scheduleFixRound")
        }
    }

    func testDocWriterTransitionsToValidation() {
        let result = makeResult(role: .docWriter)
        let task = makeTask()
        let action = handler.handleSuccess(result: result, task: task)
        XCTAssertEqual(action, .transitionToValidation(taskId: "T1"))
    }

    func testSecurityAuditorBlocksOnVulnerabilities() {
        let result = makeResult(role: .securityAuditor)
        let task = makeTask()
        let action = handler.handleSuccess(
            result: result, task: task, hasCriticalFindings: true
        )
        if case .blockTask(let tid, _) = action {
            XCTAssertEqual(tid, "T1")
        } else {
            XCTFail("Expected blockTask")
        }
    }

    // MARK: - Failure Handling

    func testFailureWithRetryAvailable() {
        let result = makeResult(success: false, error: "timeout")
        let task = TaskNode(taskId: "T1", title: "Test", attempts: 0, maxAttempts: 3)
        let action = handler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: 1,
            errorBudget: ErrorBudget(),
            totalTasks: 10,
            failedTaskCount: 1
        )
        if case .retryTask(let tid, let delay) = action {
            XCTAssertEqual(tid, "T1")
            XCTAssertGreaterThan(delay, 0)
        } else {
            XCTFail("Expected retryTask, got \(action)")
        }
    }

    func testFailureExhaustedRetries() {
        let result = makeResult(success: false, error: "timeout")
        let task = TaskNode(taskId: "T1", title: "Test", attempts: 3, maxAttempts: 3)
        let action = handler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: 1,
            errorBudget: ErrorBudget(),
            totalTasks: 10,
            failedTaskCount: 1
        )
        if case .failTask(let tid, _) = action {
            XCTAssertEqual(tid, "T1")
        } else {
            XCTFail("Expected failTask")
        }
    }

    func testFailureNonRetryableError() {
        let result = makeResult(success: false, error: "validation_error")
        let task = TaskNode(taskId: "T1", title: "Test", attempts: 0, maxAttempts: 3)
        let action = handler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: 1,
            errorBudget: ErrorBudget(),
            totalTasks: 10,
            failedTaskCount: 1
        )
        if case .failTask(_, _) = action {
            // OK
        } else {
            XCTFail("Expected failTask for non-retryable error")
        }
    }

    // MARK: - Circuit Breaker

    func testCircuitBreakerTripsOnConsecutiveFailures() {
        let result = makeResult(success: false, error: "error")
        let task = makeTask()
        let action = handler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: 5,
            errorBudget: ErrorBudget(maxConsecutiveFailures: 5),
            totalTasks: 10,
            failedTaskCount: 2
        )
        if case .abortJob(_) = action {
            // OK
        } else {
            XCTFail("Expected abortJob from circuit breaker")
        }
    }

    func testCircuitBreakerDisabledForSmallJobs() {
        let trips = handler.shouldTripCircuitBreaker(
            consecutiveFailures: 10,
            errorBudget: ErrorBudget(),
            totalTasks: 3,
            failedTaskCount: 3
        )
        XCTAssertFalse(trips)
    }

    // MARK: - Retry Delay

    func testRetryDelayExponential() {
        let d1 = handler.calculateRetryDelay(attempt: 1)
        let d2 = handler.calculateRetryDelay(attempt: 2)
        let d3 = handler.calculateRetryDelay(attempt: 3)
        XCTAssertLessThan(d1, d2)
        XCTAssertLessThan(d2, d3)
    }

    func testRetryDelayCapped() {
        let d = handler.calculateRetryDelay(attempt: 20)
        XCTAssertLessThanOrEqual(d, 30_000)
    }

    // MARK: - DocWriter Rules

    func testDocWriterForFeature() {
        let task = makeTask(taskType: .feature)
        XCTAssertTrue(handler.shouldInvokeDocWriter(task: task))
    }

    func testDocWriterForHighRisk() {
        let task = makeTask(taskType: .bugfix)
        XCTAssertTrue(handler.shouldInvokeDocWriter(task: task, riskScore: 0.6))
    }

    func testDocWriterSkippedForPureTest() {
        let task = TaskNode(taskId: "T1", title: "Test", taskType: .test, fileScope: [])
        XCTAssertFalse(handler.shouldInvokeDocWriter(task: task))
    }

    // MARK: - Retryable Errors

    func testRetryableErrorClassification() {
        XCTAssertTrue(TaskCompletionHandler.isRetryableError("timeout"))
        XCTAssertTrue(TaskCompletionHandler.isRetryableError("network_error"))
        XCTAssertTrue(TaskCompletionHandler.isRetryableError(nil))
        XCTAssertFalse(TaskCompletionHandler.isRetryableError("validation_error"))
        XCTAssertFalse(TaskCompletionHandler.isRetryableError("security_block"))
        XCTAssertFalse(TaskCompletionHandler.isRetryableError("permission_denied"))
    }
}
