import XCTest
@testable import CoderIDE

final class CLIProfileProvisionerInstructionSyncSubagentRoutingTests: XCTestCase {
    func testCodexInstructionsTemplatePrefersSoloCodeSubagentToolsOverProviderForking() {
        let template = CLIProfileProvisioner.codexInstructionsTemplate
        let normalized = template.lowercased()

        XCTAssertTrue(normalized.contains("native `subagent_*` tools"))
        XCTAssertTrue(normalized.contains("do not switch to provider-native fork/collaboration apis first"))
        XCTAssertTrue(normalized.contains("do not mention fork/fork_context limitations"))
        XCTAssertTrue(normalized.contains("coderide_subagent_*"))
        XCTAssertTrue(normalized.contains("proxy for real subagent execution"))
        XCTAssertTrue(template.contains("`subagent_reviewer`"))
        XCTAssertTrue(template.contains("`subagent_testWriter`"))
    }
}
