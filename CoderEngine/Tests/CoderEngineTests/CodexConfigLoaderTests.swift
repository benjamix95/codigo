import XCTest
@testable import CoderEngine

final class CodexConfigLoaderTests: XCTestCase {
    func testParseReadsFastModeFromTopLevelConfig() {
        let parsed = CodexConfigLoader.parse(
            """
            sandbox_mode = "danger-full-access"
            fast_mode = true
            model = "gpt-5-codex"
            """
        )

        XCTAssertEqual(parsed.sandboxMode, "danger-full-access")
        XCTAssertEqual(parsed.fastMode, true)
        XCTAssertEqual(parsed.model, "gpt-5-codex")
    }
}
