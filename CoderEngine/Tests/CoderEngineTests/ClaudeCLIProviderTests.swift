import XCTest
@testable import CoderEngine

final class ClaudeCLIProviderTests: XCTestCase {
    func testNormalizeToolsFallsBackToDefaultToolsWhenListIsEmpty() {
        XCTAssertEqual(
            ClaudeCLIProvider.normalizeTools([]),
            ["Read", "Edit", "Bash", "Write", "Search", "Task"]
        )
    }

    func testBuildCLIArgumentsAlwaysIncludesAllowedToolsForEmptyConfiguration() {
        let args = ClaudeCLIProvider.buildCLIArguments(
            fullPrompt: "prompt",
            model: nil,
            allowedTools: ClaudeCLIProvider.normalizeTools([])
        )

        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("Read,Edit,Bash,Write,Search,Task"))
    }
}
