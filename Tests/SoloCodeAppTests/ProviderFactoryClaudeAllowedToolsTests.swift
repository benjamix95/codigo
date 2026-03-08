import XCTest
import CoderEngine
@testable import CoderIDE

final class ProviderFactoryClaudeAllowedToolsTests: XCTestCase {
    func testLegacyClaudeDefaultPresetIsAutoMigratedWithTask() {
        let parsed = ProviderFactory.normalizedToolList(from: "Read,Edit,Bash,Write,Search")

        XCTAssertEqual(parsed, ["Read", "Edit", "Bash", "Write", "Search", "Task"])
    }

    func testCustomClaudePresetWithoutTaskIsPreserved() {
        let parsed = ProviderFactory.normalizedToolList(from: "Read,Search")

        XCTAssertEqual(parsed, ["Read", "Search"])
    }

    func testPresetWithTaskRemainsStableAndDeduplicated() {
        let parsed = ProviderFactory.normalizedToolList(
            from: "Read,Edit,Bash,Write,Search,Task,Task")

        XCTAssertEqual(parsed, ["Read", "Edit", "Bash", "Write", "Search", "Task"])
    }

    func testClaudeToolsAreRestrictedToReadOnlyWhenMutationsDisabled() {
        let configuredTools = ["Read", "Edit", "Bash", "Write", "Search", "Task", "Glob", "Grep"]
        let readOnlyPolicy = ToolRuntimePolicy(allowMutatingTools: false)

        let effective = ProviderFactory.claudeTools(
            from: configuredTools,
            toolPolicy: readOnlyPolicy
        )

        XCTAssertEqual(effective, ["Read", "Search", "Glob", "Grep"])
    }

    func testClaudeToolsFallbackToReadWhenReadOnlyFilterEmptiesList() {
        let configuredTools = ["Edit", "Bash", "Write"]
        let readOnlyPolicy = ToolRuntimePolicy(allowMutatingTools: false)

        let effective = ProviderFactory.claudeTools(
            from: configuredTools,
            toolPolicy: readOnlyPolicy
        )

        XCTAssertEqual(effective, ["Read"])
    }
}
