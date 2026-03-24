import XCTest
@testable import CoderIDE

final class CodexLoginServiceTests: XCTestCase {
    func testLoginWithAPIKeyFailsForInvalidPath() async {
        let result = await CodexLoginService.loginWithAPIKey(
            codexPath: "/nonexistent/codex",
            apiKey: "test-key"
        )

        switch result {
        case .failure:
            break // Expected
        case .success:
            XCTFail("Should fail with invalid codex path")
        case .timeout:
            XCTFail("Should fail immediately, not timeout")
        }
    }

    func testRunBrowserLoginFailsForInvalidPath() async {
        let result = await CodexLoginService.runBrowserLogin(
            codexPath: "/nonexistent/codex",
            args: []
        )

        switch result {
        case .failure:
            break // Expected
        case .success:
            XCTFail("Should fail with invalid codex path")
        case .timeout:
            XCTFail("Should fail immediately, not timeout")
        }
    }

    func testPollForCompletionReturnsFalseForInvalidPath() async {
        let ready = await CodexLoginService.pollForCompletion(
            codexPath: "/nonexistent/codex",
            maxAttempts: 1,
            intervalSeconds: 0
        )

        XCTAssertFalse(ready, "Should not find login status for invalid path")
    }

    func testLoginResultEquality() {
        // Verify the enum cases exist and are distinct
        let success = CodexLoginService.LoginResult.success
        let failure = CodexLoginService.LoginResult.failure("error")
        let timeout = CodexLoginService.LoginResult.timeout

        switch success {
        case .success: break
        default: XCTFail("Expected success")
        }

        switch failure {
        case .failure(let msg):
            XCTAssertEqual(msg, "error")
        default: XCTFail("Expected failure")
        }

        switch timeout {
        case .timeout: break
        default: XCTFail("Expected timeout")
        }
    }
}
