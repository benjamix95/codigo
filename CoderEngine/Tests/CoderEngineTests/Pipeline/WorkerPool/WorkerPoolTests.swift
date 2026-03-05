import XCTest
@testable import CoderEngine

final class WorkerPoolTests: XCTestCase {

    // MARK: - Dispatch

    func testDispatchAndCollect() async throws {
        let pool = WorkerPool(maxWorkers: 4)

        try await pool.dispatch(
            taskId: "T1",
            agentName: "Test-coder",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "T1",
                agentName: "Test-coder",
                agentRole: .coder,
                success: true,
                durationMs: 100
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let results = await pool.collectResults()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.taskId, "T1")
        XCTAssertTrue(results.first?.success ?? false)
    }

    func testActiveCountUpdated() async throws {
        let pool = WorkerPool(maxWorkers: 4)
        let expectation = XCTestExpectation(description: "work completes")

        try await pool.dispatch(
            taskId: "T1",
            agentName: "Test-coder",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            expectation.fulfill()
            return WorkerTaskResult(
                taskId: "T1",
                agentName: "Test-coder",
                agentRole: .coder,
                success: true
            )
        }

        let active = await pool.activeCount
        XCTAssertEqual(active, 1)
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Capacity

    func testAtCapacityBlocks() async throws {
        let pool = WorkerPool(maxWorkers: 1)

        try await pool.dispatch(
            taskId: "T1",
            agentName: "T1-coder",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return WorkerTaskResult(
                taskId: "T1",
                agentName: "T1-coder",
                agentRole: .coder,
                success: true
            )
        }

        do {
            try await pool.dispatch(
                taskId: "T2",
                agentName: "T2-coder",
                agentRole: .coder
            ) {
                WorkerTaskResult(
                    taskId: "T2",
                    agentName: "T2-coder",
                    agentRole: .coder,
                    success: true
                )
            }
            XCTFail("Should throw at capacity")
        } catch let error as WorkerPoolError {
            XCTAssertEqual(error, .atCapacity)
        }
    }

    func testDuplicateTaskIdRejected() async throws {
        let pool = WorkerPool(maxWorkers: 4)

        try await pool.dispatch(
            taskId: "T1",
            agentName: "T1-coder",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return WorkerTaskResult(
                taskId: "T1",
                agentName: "T1-coder",
                agentRole: .coder,
                success: true
            )
        }

        do {
            try await pool.dispatch(
                taskId: "T1",
                agentName: "T1-reviewer",
                agentRole: .reviewer
            ) {
                WorkerTaskResult(
                    taskId: "T1",
                    agentName: "T1-reviewer",
                    agentRole: .reviewer,
                    success: true
                )
            }
            XCTFail("Should throw duplicate")
        } catch let error as WorkerPoolError {
            XCTAssertEqual(error, .taskAlreadyRunning(taskId: "T1"))
        }
    }

    // MARK: - Shutdown

    func testShutdownRejectsDispatch() async throws {
        let pool = WorkerPool(maxWorkers: 4)
        await pool.shutdown()

        do {
            try await pool.dispatch(
                taskId: "T1",
                agentName: "T1-coder",
                agentRole: .coder
            ) {
                WorkerTaskResult(
                    taskId: "T1",
                    agentName: "T1-coder",
                    agentRole: .coder,
                    success: true
                )
            }
            XCTFail("Should throw shutdown")
        } catch let error as WorkerPoolError {
            XCTAssertEqual(error, .poolShutdown)
        }
    }

    // MARK: - Metrics

    func testMetricsTracked() async throws {
        let pool = WorkerPool(maxWorkers: 4)

        try await pool.dispatch(
            taskId: "T1",
            agentName: "T1-coder",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "T1",
                agentName: "T1-coder",
                agentRole: .coder,
                success: true
            )
        }

        try await pool.dispatch(
            taskId: "T2",
            agentName: "T2-coder",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "T2",
                agentName: "T2-coder",
                agentRole: .coder,
                success: false,
                error: "timeout"
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let dispatched = await pool.totalDispatched
        XCTAssertEqual(dispatched, 2)
    }

    // MARK: - Max Workers Clamped

    func testMaxWorkersClamped() async {
        let pool = WorkerPool(maxWorkers: 100)
        let max = await pool.maxWorkers
        XCTAssertLessThanOrEqual(max, 8)
    }

    func testMaxWorkersMinimumOne() async {
        let pool = WorkerPool(maxWorkers: 0)
        let max = await pool.maxWorkers
        XCTAssertGreaterThanOrEqual(max, 1)
    }
}
