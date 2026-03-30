import XCTest
@testable import CoderIDE

final class CLIProfileProvisionerInstructionSyncSubagentRoutingTests: XCTestCase {
    func testCodexInstructionsTemplatePrefersNativeSubagentLifecycle() {
        let template = CLIProfileProvisioner.codexInstructionsTemplate

        XCTAssertTrue(template.contains("provider-native subagent/task capability"))
        XCTAssertTrue(template.contains("Do NOT use `coderide_subagent_*` as a proxy"))
        XCTAssertTrue(template.contains("`subagent_reviewer`"))
        XCTAssertTrue(template.contains("`subagent_testWriter`"))
    }
}
