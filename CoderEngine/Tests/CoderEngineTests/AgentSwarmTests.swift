import XCTest
@testable import CoderEngine

final class AgentSwarmTests: XCTestCase {
    func testSwarmConfigDefaultInit() {
        let config = SwarmConfig()
        XCTAssertEqual(config.orchestratorBackend, .openai)
        XCTAssertEqual(config.maxRounds, 1)
        XCTAssertTrue(config.autoPostCodePipeline)
        XCTAssertEqual(config.maxPostCodeRetries, 10)
        XCTAssertEqual(config.enabledRoles, Set(AgentRole.allCases))
    }

    func testSwarmConfigAutoPostCodePipeline() {
        let config = SwarmConfig(autoPostCodePipeline: false)
        XCTAssertFalse(config.autoPostCodePipeline)
    }

    func testAgentRoleAllCases() {
        let roles = AgentRole.allCases
        XCTAssertEqual(roles.count, 7)
        XCTAssertTrue(roles.contains(.planner))
        XCTAssertTrue(roles.contains(.coder))
        XCTAssertTrue(roles.contains(.debugger))
        XCTAssertTrue(roles.contains(.reviewer))
        XCTAssertTrue(roles.contains(.docWriter))
        XCTAssertTrue(roles.contains(.securityAuditor))
        XCTAssertTrue(roles.contains(.testWriter))
    }

    func testAgentTaskEncodeDecode() throws {
        let task = AgentTask(role: .coder, taskDescription: "Implement feature X", order: 1)
        let encoder = JSONEncoder()
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentTask.self, from: data)
        XCTAssertEqual(decoded.role, .coder)
        XCTAssertEqual(decoded.taskDescription, "Implement feature X")
        XCTAssertEqual(decoded.order, 1)
    }
}
