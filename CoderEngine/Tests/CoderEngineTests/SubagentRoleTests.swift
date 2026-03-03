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

    func testCanEditFilesMatchesReadOnlyRoles() {
        XCTAssertFalse(SubagentRole.explorer.canEditFiles)
        XCTAssertFalse(SubagentRole.reviewer.canEditFiles)
        XCTAssertFalse(SubagentRole.securityAuditor.canEditFiles)
        XCTAssertTrue(SubagentRole.coder.canEditFiles)
        XCTAssertTrue(SubagentRole.debugger.canEditFiles)
        XCTAssertTrue(SubagentRole.testWriter.canEditFiles)
        XCTAssertTrue(SubagentRole.docWriter.canEditFiles)
    }

    func testMaxToolRoundsAreRoleSpecific() {
        XCTAssertEqual(SubagentRole.explorer.maxToolRounds, 40)
        XCTAssertEqual(SubagentRole.reviewer.maxToolRounds, 50)
        XCTAssertEqual(SubagentRole.securityAuditor.maxToolRounds, 50)
        XCTAssertEqual(SubagentRole.testWriter.maxToolRounds, 100)
        XCTAssertEqual(SubagentRole.coder.maxToolRounds, 80)
        XCTAssertEqual(SubagentRole.debugger.maxToolRounds, 80)
        XCTAssertEqual(SubagentRole.docWriter.maxToolRounds, 80)
    }
}
