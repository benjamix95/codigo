import XCTest
@testable import CoderEngine

final class DagSchedulerTests: XCTestCase {

    // MARK: - Task Management

    func testAddAndRetrieveTask() async throws {
        let scheduler = DagScheduler()
        let task = TaskNode(taskId: "T1", title: "First task")
        try await scheduler.addTask(task)

        let retrieved = await scheduler.task(byId: "T1")
        XCTAssertEqual(retrieved?.taskId, "T1")
        let count = await scheduler.taskCount
        XCTAssertEqual(count, 1)
    }

    func testDuplicateTaskIdThrows() async throws {
        let scheduler = DagScheduler()
        let t1 = TaskNode(taskId: "T1", title: "First")
        try await scheduler.addTask(t1)

        let t1dup = TaskNode(taskId: "T1", title: "Duplicate")
        do {
            try await scheduler.addTask(t1dup)
            XCTFail("Should throw duplicate")
        } catch let error as DagSchedulerError {
            if case .duplicateTaskId(let id) = error {
                XCTAssertEqual(id, "T1")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Ready Tasks

    func testReadyTasksNoDeps() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A", priority: 50))
        try await scheduler.addTask(TaskNode(taskId: "T2", title: "B", priority: 80))

        let ready = await scheduler.getReadyTasks()
        XCTAssertEqual(ready.map(\.taskId), ["T2", "T1"])
    }

    func testReadyTasksWithDeps() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A"))
        try await scheduler.addTask(TaskNode(
            taskId: "T2", title: "B", dependsOn: ["T1"]
        ))

        var ready = await scheduler.getReadyTasks()
        XCTAssertEqual(ready.map(\.taskId), ["T1"])

        await scheduler.updateTaskStatus("T1", status: .completed)
        ready = await scheduler.getReadyTasks()
        XCTAssertEqual(ready.map(\.taskId), ["T2"])
    }

    func testRunningTaskNotReady() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A"))
        await scheduler.updateTaskStatus("T1", status: .running)

        let ready = await scheduler.getReadyTasks()
        XCTAssertTrue(ready.isEmpty)
    }

    // MARK: - Lowest Risk

    func testLowestRiskReadyTask() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(
            taskId: "T1", title: "High risk", risk: .high
        ))
        try await scheduler.addTask(TaskNode(
            taskId: "T2", title: "Low risk", risk: .low
        ))

        let lowest = await scheduler.getLowestRiskReadyTask()
        XCTAssertEqual(lowest?.taskId, "T2")
    }

    // MARK: - Retry

    func testScheduleRetry() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A"))
        await scheduler.updateTaskStatus("T1", status: .failed)

        await scheduler.scheduleRetry("T1")
        let task = await scheduler.task(byId: "T1")
        XCTAssertEqual(task?.status, .pending)
        XCTAssertEqual(task?.attempts, 1)
        XCTAssertNotNil(task?.waitingSince)
    }

    // MARK: - Validation

    func testValidateDependenciesMissing() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(
            taskId: "T1", title: "A", dependsOn: ["MISSING"]
        ))

        do {
            try await scheduler.validateDependencies()
            XCTFail("Should throw")
        } catch let error as DagSchedulerError {
            if case .dependencyNotFound(let taskId, let missing) = error {
                XCTAssertEqual(taskId, "T1")
                XCTAssertEqual(missing, "MISSING")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testValidateAcyclicPasses() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A"))
        try await scheduler.addTask(TaskNode(
            taskId: "T2", title: "B", dependsOn: ["T1"]
        ))
        try await scheduler.validateAcyclic()
    }

    func testValidateAcyclicDetectsCycle() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(
            taskId: "T1", title: "A", dependsOn: ["T2"]
        ))
        try await scheduler.addTask(TaskNode(
            taskId: "T2", title: "B", dependsOn: ["T1"]
        ))

        do {
            try await scheduler.validateAcyclic()
            XCTFail("Should detect cycle")
        } catch let error as DagSchedulerError {
            if case .cyclicDependency(let involved) = error {
                XCTAssertTrue(involved.contains("T1"))
                XCTAssertTrue(involved.contains("T2"))
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Terminal Check

    func testAllTasksTerminal() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTask(TaskNode(taskId: "T1", title: "A"))
        try await scheduler.addTask(TaskNode(taskId: "T2", title: "B"))

        var allDone = await scheduler.allTasksTerminal
        XCTAssertFalse(allDone)

        await scheduler.updateTaskStatus("T1", status: .completed)
        await scheduler.updateTaskStatus("T2", status: .failed)

        allDone = await scheduler.allTasksTerminal
        XCTAssertTrue(allDone)
    }

    // MARK: - Failure Rate

    func testFailureRatePercent() async throws {
        let scheduler = DagScheduler()
        try await scheduler.addTasks([
            TaskNode(taskId: "T1", title: "A"),
            TaskNode(taskId: "T2", title: "B"),
            TaskNode(taskId: "T3", title: "C"),
            TaskNode(taskId: "T4", title: "D")
        ])
        await scheduler.updateTaskStatus("T1", status: .completed)
        await scheduler.updateTaskStatus("T2", status: .failed)

        let rate = await scheduler.failureRatePercent
        XCTAssertEqual(rate, 25.0, accuracy: 0.1)
    }
}
