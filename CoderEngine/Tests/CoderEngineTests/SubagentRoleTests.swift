import XCTest
@testable import CoderEngine

final class SubagentRoleTests: XCTestCase {
    func testFromToolNameSupportsCanonicalAndNormalizedVariants() {
        XCTAssertEqual(SubagentRole.fromToolName("subagent_explorer"), .explorer)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_debugger"), .debugger)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_testWriter"), .testWriter)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_testwriter"), .testWriter)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_test_writer"), .testWriter)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_docWriter"), .docWriter)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_doc_writer"), .docWriter)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_securityAuditor"), .securityAuditor)
        XCTAssertEqual(SubagentRole.fromToolName("subagent_security_auditor"), .securityAuditor)
    }

    func testFromToolNameSupportsLegacyTesterAlias() {
        XCTAssertEqual(SubagentRole.fromToolName("subagent_tester"), .testWriter)
    }
}

