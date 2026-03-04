import XCTest
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
}
