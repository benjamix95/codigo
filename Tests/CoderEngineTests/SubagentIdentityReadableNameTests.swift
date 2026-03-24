import XCTest
@testable import CoderEngine

final class SubagentIdentityReadableNameTests: XCTestCase {

    func testReadableDisplayNameExtractsKeyWords() {
        let name = SubagentExecutionIdentityBuilder.readableDisplayName(
            from: "Investigate the auth token refresh flow and session invalidation",
            role: .explorer
        )
        // Should have space-separated words, no filler words
        XCTAssertFalse(name.isEmpty)
        XCTAssertTrue(name.contains(" "), "Should have spaces between words: \(name)")
        XCTAssertFalse(name.contains("the"), "Should strip filler words")
        XCTAssertFalse(name.contains("and"), "Should strip filler words")
    }

    func testReadableDisplayNameCapsAt5Words() {
        let name = SubagentExecutionIdentityBuilder.readableDisplayName(
            from: "First second third fourth fifth sixth seventh eighth ninth tenth",
            role: nil
        )
        let wordCount = name.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 5)
    }

    func testReadableDisplayNameFallsBackToRoleName() {
        let name = SubagentExecutionIdentityBuilder.readableDisplayName(
            from: "",
            role: .explorer
        )
        // Empty task should fall back
        XCTAssertTrue(name.isEmpty || name == "Explorer")
    }

    func testMakeIncludesReadableName() {
        let identity = SubagentExecutionIdentityBuilder.make(
            role: .explorer,
            task: "Analyze database connection pooling configuration"
        )
        XCTAssertFalse(identity.readableName.isEmpty)
        XCTAssertTrue(identity.readableName.contains(" "),
                      "readableName should have spaces: \(identity.readableName)")
        // Should not be the same as agentName (which is CamelCase)
        XCTAssertNotEqual(identity.readableName, identity.agentName)
    }

    func testTaskSummaryMaxLength500() {
        let longTask = String(repeating: "a", count: 600)
        let summary = SubagentExecutionIdentityBuilder.taskSummary(from: longTask)
        XCTAssertEqual(summary.count, 500)
    }

    func testTaskSummaryPreservesShortTasks() {
        let task = "Short task description"
        let summary = SubagentExecutionIdentityBuilder.taskSummary(from: task)
        XCTAssertEqual(summary, task)
    }
}
