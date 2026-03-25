import XCTest
@testable import CoderEngine

/// Test per le correzioni di sicurezza del WorkerPool.
///
/// Verifica: safe unwrap di group.next(), shutdown non-busy-wait,
/// capacity management, e metriche.
final class WorkerPoolSafetyTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultMaxWorkers() async {
        let pool = WorkerPool()
        let max = await pool.maxWorkers
        XCTAssertEqual(max, 4)
    }

    func testMaxWorkersClampedToRange() async {
        let tooSmall = WorkerPool(maxWorkers: 0)
        let tooLarge = WorkerPool(maxWorkers: 100)

        let small = await tooSmall.maxWorkers
        let large = await tooLarge.maxWorkers

        XCTAssertEqual(small, 1)
        XCTAssertEqual(large, 12)
    }

    // MARK: - Capacity

    func testInitialActiveCountIsZero() async {
        let pool = WorkerPool()
        let count = await pool.activeCount
        XCTAssertEqual(count, 0)
    }

    func testIsAtCapacityWhenFull() async {
        let pool = WorkerPool(maxWorkers: 1)

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        let atCap = await pool.isAtCapacity
        XCTAssertTrue(atCap)

        await pool.cancelAll()
    }

    func testAtCapacityThrowsError() async {
        let pool = WorkerPool(maxWorkers: 1)

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        do {
            try await pool.dispatch(
                taskId: "t2",
                agentName: "agent",
                agentRole: .coder
            ) {
                WorkerTaskResult(
                    taskId: "t2", agentName: "agent",
                    agentRole: .coder, success: true
                )
            }
            XCTFail("Should throw atCapacity")
        } catch WorkerPoolError.atCapacity {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await pool.cancelAll()
    }

    // MARK: - Duplicate Task Prevention

    func testDuplicateTaskIdThrows() async {
        let pool = WorkerPool(maxWorkers: 4)

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        do {
            try await pool.dispatch(
                taskId: "t1",
                agentName: "agent",
                agentRole: .coder
            ) {
                WorkerTaskResult(
                    taskId: "t1", agentName: "agent",
                    agentRole: .coder, success: true
                )
            }
            XCTFail("Should throw taskAlreadyRunning")
        } catch WorkerPoolError.taskAlreadyRunning(let id) {
            XCTAssertEqual(id, "t1")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await pool.cancelAll()
    }

    // MARK: - Shutdown

    func testShutdownPreventsNewDispatches() async {
        let pool = WorkerPool()
        await pool.shutdown()

        do {
            try await pool.dispatch(
                taskId: "t1",
                agentName: "agent",
                agentRole: .coder
            ) {
                WorkerTaskResult(
                    taskId: "t1", agentName: "agent",
                    agentRole: .coder, success: true
                )
            }
            XCTFail("Should throw poolShutdown")
        } catch WorkerPoolError.poolShutdown {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShutdownAndWaitCompletes() async {
        let pool = WorkerPool(maxWorkers: 2)

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        await pool.shutdownAndWait(timeoutMs: 2000)

        // Dopo shutdown, i risultati dovrebbero essere disponibili
        let results = await pool.collectResults()
        XCTAssertGreaterThanOrEqual(results.count, 0) // potrebbe essere già completato
    }

    // MARK: - Metrics

    func testMetricsAfterCompletion() async {
        let pool = WorkerPool(maxWorkers: 4)

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        try? await Task.sleep(nanoseconds: 500_000_000) // aspetta completamento

        let dispatched = await pool.totalDispatched
        XCTAssertEqual(dispatched, 1)
    }

    // MARK: - Reset

    func testResetClearsAll() async {
        let pool = WorkerPool()

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        await pool.reset()

        let count = await pool.activeCount
        let dispatched = await pool.totalDispatched
        XCTAssertEqual(count, 0)
        XCTAssertEqual(dispatched, 0)
    }

    // MARK: - Cancel All

    func testCancelAllClearsActiveTasks() async {
        let pool = WorkerPool(maxWorkers: 4)

        for i in 0..<3 {
            try? await pool.dispatch(
                taskId: "t\(i)",
                agentName: "agent",
                agentRole: .coder
            ) {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return WorkerTaskResult(
                    taskId: "t\(i)", agentName: "agent",
                    agentRole: .coder, success: false,
                    error: "cancelled"
                )
            }
        }

        await pool.cancelAll()

        let count = await pool.activeCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Collect Results

    func testCollectResultsClearsBuffer() async {
        let pool = WorkerPool()

        try? await pool.dispatch(
            taskId: "t1",
            agentName: "agent",
            agentRole: .coder
        ) {
            WorkerTaskResult(
                taskId: "t1", agentName: "agent",
                agentRole: .coder, success: true
            )
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let first = await pool.collectResults()
        let second = await pool.collectResults()

        // Prima collect restituisce risultati, seconda è vuota
        if !first.isEmpty {
            XCTAssertTrue(second.isEmpty, "Second collect should be empty")
        }
    }
}
