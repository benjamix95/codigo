import XCTest
@testable import CoderEngine

final class PipelineEnumsTests: XCTestCase {

    // MARK: - JobState

    func testJobState_roundTripCoding() throws {
        for state in JobState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(JobState.self, from: data)
            XCTAssertEqual(state, decoded, "Round-trip failed for \(state)")
        }
    }

    func testJobState_terminalStates() {
        XCTAssertTrue(JobState.finalized.isTerminal)
        XCTAssertTrue(JobState.aborted.isTerminal)
        XCTAssertFalse(JobState.executing.isTerminal)
        XCTAssertFalse(JobState.failed.isTerminal)
    }

    func testJobState_validTransitions() {
        XCTAssertTrue(JobState.intake.canTransition(to: .planning))
        XCTAssertFalse(JobState.intake.canTransition(to: .executing))
        XCTAssertTrue(JobState.executing.canTransition(to: .reviewing))
        XCTAssertTrue(JobState.executing.canTransition(to: .failed))
        XCTAssertFalse(JobState.executing.canTransition(to: .finalized))
        XCTAssertTrue(JobState.applying.canTransition(to: .rollingBack))
        XCTAssertTrue(JobState.failed.canTransition(to: .retrying))
        XCTAssertTrue(JobState.failed.canTransition(to: .circuitBroken))
        XCTAssertTrue(JobState.circuitBroken.canTransition(to: .aborted))
        XCTAssertFalse(JobState.circuitBroken.canTransition(to: .scheduled))
    }

    func testJobState_terminalHaveNoTransitions() {
        XCTAssertTrue(JobState.finalized.validTransitions.isEmpty)
        XCTAssertTrue(JobState.aborted.validTransitions.isEmpty)
    }

    // MARK: - TaskType

    func testTaskType_roundTripCoding() throws {
        for tt in TaskType.allCases {
            let data = try JSONEncoder().encode(tt)
            let decoded = try JSONDecoder().decode(TaskType.self, from: data)
            XCTAssertEqual(tt, decoded)
        }
    }

    // MARK: - AgentRole

    func testAgentRole_readOnlyRoles() {
        XCTAssertTrue(AgentRole.planner.isReadOnly)
        XCTAssertTrue(AgentRole.explorer.isReadOnly)
        XCTAssertTrue(AgentRole.reviewer.isReadOnly)
        XCTAssertTrue(AgentRole.securityAuditor.isReadOnly)
        XCTAssertFalse(AgentRole.coder.isReadOnly)
        XCTAssertFalse(AgentRole.debugger.isReadOnly)
        XCTAssertFalse(AgentRole.testWriter.isReadOnly)
        XCTAssertFalse(AgentRole.docWriter.isReadOnly)
    }

    func testAgentRole_roundTripCoding() throws {
        for role in AgentRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(AgentRole.self, from: data)
            XCTAssertEqual(role, decoded)
        }
    }

    // MARK: - RollbackStrategy

    func testRollbackStrategy_jsonValues() throws {
        let encoder = JSONEncoder()
        let gitBranch = try encoder.encode(RollbackStrategy.gitBranch)
        XCTAssertEqual(String(data: gitBranch, encoding: .utf8), "\"git_branch\"")

        let gitStash = try encoder.encode(RollbackStrategy.gitStash)
        XCTAssertEqual(String(data: gitStash, encoding: .utf8), "\"git_stash\"")

        let fs = try encoder.encode(RollbackStrategy.filesystemSnapshot)
        XCTAssertEqual(String(data: fs, encoding: .utf8), "\"filesystem_snapshot\"")
    }

    // MARK: - PipelineEventType

    func testPipelineEventType_roundTripCoding() throws {
        for evt in PipelineEventType.allCases {
            let data = try JSONEncoder().encode(evt)
            let decoded = try JSONDecoder().decode(PipelineEventType.self, from: data)
            XCTAssertEqual(evt, decoded)
        }
    }

    // MARK: - CircuitBreakerPhase

    func testCircuitBreakerPhase_jsonValues() throws {
        let encoder = JSONEncoder()
        let halfOpen = try encoder.encode(CircuitBreakerPhase.halfOpen)
        XCTAssertEqual(String(data: halfOpen, encoding: .utf8), "\"half_open\"")
    }

    // MARK: - ActionType

    func testActionType_roundTripCoding() throws {
        for at in ActionType.allCases {
            let data = try JSONEncoder().encode(at)
            let decoded = try JSONDecoder().decode(ActionType.self, from: data)
            XCTAssertEqual(at, decoded)
        }
    }

    // MARK: - SemanticChangeType & Impact

    func testSemanticChangeType_allCases() {
        XCTAssertEqual(SemanticChangeType.allCases.count, 11)
    }

    func testSemanticImpact_allCases() {
        XCTAssertEqual(SemanticImpact.allCases.count, 4)
    }

    // MARK: - PipelineMode

    func testPipelineMode_roundTrip() throws {
        for mode in PipelineMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PipelineMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }
}
