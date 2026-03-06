import XCTest
@testable import CoderEngine

final class TaskNodeTests: XCTestCase {

    // MARK: - Default values

    func testTaskNode_defaultValues() {
        let node = TaskNode(taskId: "T1", title: "Test task")
        XCTAssertEqual(node.priority, 50)
        XCTAssertEqual(node.risk, .medium)
        XCTAssertEqual(node.taskType, .feature)
        XCTAssertEqual(node.executionStyle, .multiAgentFlow)
        XCTAssertNil(node.preferredAgentRole)
        XCTAssertNil(node.debugStage)
        XCTAssertTrue(node.metadata.isEmpty)
        XCTAssertEqual(node.status, .pending)
        XCTAssertEqual(node.attempts, 0)
        XCTAssertEqual(node.maxAttempts, 3)
        XCTAssertEqual(node.timeoutMs, 120_000)
        XCTAssertTrue(node.dependsOn.isEmpty)
        XCTAssertFalse(node.contextEnriched)
    }

    // MARK: - Identifiable

    func testTaskNode_identifiable() {
        let node = TaskNode(taskId: "T42", title: "Some task")
        XCTAssertEqual(node.id, "T42")
    }

    // MARK: - Coding round-trip

    func testTaskNode_codingRoundTrip() throws {
        let node = TaskNode(
            taskId: "T3",
            title: "Refactor parser lock handling",
            dependsOn: ["T1", "T2"],
            priority: 70,
            risk: .high,
            taskType: .refactor,
            executionStyle: .singleAgent,
            preferredAgentRole: .debugger,
            debugStage: .fix,
            fileScope: ["Sources/A.swift", "Sources/B.swift"],
            symbolScope: ["ParserLock", "LockManager"],
            metadata: ["origin": "tests"],
            maxAttempts: 5,
            timeoutMs: 180_000
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(node)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskNode.self, from: data)

        XCTAssertEqual(node.taskId, decoded.taskId)
        XCTAssertEqual(node.dependsOn, decoded.dependsOn)
        XCTAssertEqual(node.priority, decoded.priority)
        XCTAssertEqual(node.risk, decoded.risk)
        XCTAssertEqual(node.taskType, decoded.taskType)
        XCTAssertEqual(node.executionStyle, decoded.executionStyle)
        XCTAssertEqual(node.preferredAgentRole, decoded.preferredAgentRole)
        XCTAssertEqual(node.debugStage, decoded.debugStage)
        XCTAssertEqual(node.fileScope, decoded.fileScope)
        XCTAssertEqual(node.symbolScope, decoded.symbolScope)
        XCTAssertEqual(node.metadata, decoded.metadata)
    }

    // MARK: - JSON key format

    func testTaskNode_jsonKeys() throws {
        let node = TaskNode(
            taskId: "T1",
            title: "t",
            executionStyle: .singleAgent,
            preferredAgentRole: .debugger,
            debugStage: .fix,
            metadata: ["origin": "tests"]
        )
        let data = try JSONEncoder().encode(node)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"task_id\""))
        XCTAssertTrue(json.contains("\"depends_on\""))
        XCTAssertTrue(json.contains("\"task_type\""))
        XCTAssertTrue(json.contains("\"execution_style\""))
        XCTAssertTrue(json.contains("\"preferred_agent_role\""))
        XCTAssertTrue(json.contains("\"debug_stage\""))
        XCTAssertTrue(json.contains("\"file_scope\""))
        XCTAssertTrue(json.contains("\"symbol_scope\""))
        XCTAssertTrue(json.contains("\"metadata\""))
        XCTAssertTrue(json.contains("\"max_attempts\""))
        XCTAssertTrue(json.contains("\"timeout_ms\""))
    }

    // MARK: - deriveTaskLabel

    func testTaskNode_deriveTaskLabel() {
        var node = TaskNode(taskId: "T1", title: "Refactor parser lock handling")
        node.deriveTaskLabel()
        XCTAssertEqual(node.taskLabel, "RefactorParserLockHandling")
    }

    func testTaskNode_deriveTaskLabel_truncation() {
        var node = TaskNode(
            taskId: "T1",
            title: "This is a very long task title that should be truncated to thirty characters max"
        )
        node.deriveTaskLabel()
        XCTAssertNotNil(node.taskLabel)
        XCTAssertLessThanOrEqual(node.taskLabel!.count, 30)
    }

    // MARK: - Validation

    func testTaskNode_validationPass() throws {
        let node = TaskNode(taskId: "T1", title: "Valid task")
        XCTAssertNoThrow(try node.validate())
    }

    func testTaskNode_emptyTaskId_fails() {
        let node = TaskNode(taskId: "", title: "Task")
        XCTAssertThrowsError(try node.validate())
    }

    func testTaskNode_priorityOutOfRange_fails() {
        let node = TaskNode(taskId: "T1", title: "Task", priority: 150)
        XCTAssertThrowsError(try node.validate())
    }

    func testTaskNode_attemptsExceedMax_fails() {
        let node = TaskNode(
            taskId: "T1", title: "Task",
            attempts: 5, maxAttempts: 3
        )
        XCTAssertThrowsError(try node.validate())
    }

    func testTaskNode_timeoutTooLow_fails() {
        let node = TaskNode(taskId: "T1", title: "Task", timeoutMs: 100)
        XCTAssertThrowsError(try node.validate())
    }

    func testTaskNode_singleAgentRequiresPreferredRole() {
        let node = TaskNode(
            taskId: "T1",
            title: "Debug stage",
            executionStyle: .singleAgent
        )
        XCTAssertThrowsError(try node.validate())
    }

    // MARK: - ActiveAgent

    func testActiveAgent_codingRoundTrip() throws {
        let agent = ActiveAgent(
            agentName: "RefactorParser-coder",
            agentId: "agent_01",
            status: .running
        )
        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(ActiveAgent.self, from: data)
        XCTAssertEqual(agent, decoded)
    }
}
