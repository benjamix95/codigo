import XCTest
@testable import CoderIDE

final class CLIAccountLoginCoordinatorTests: XCTestCase {
    func testOutputRequestsInteractiveCodeForClaudeAuthenticationScreen() {
        let output = """
        Authentication Code
        Paste this into Claude Code:
        APE1K6LKUDhLHqpLr0s6DTLDBA5DKB7YRigiXZAeXexAD6X9
        """

        XCTAssertTrue(
            CLIAccountLoginCoordinator.outputRequestsInteractiveCode(output, provider: .claude)
        )
    }

    func testOutputRequestsInteractiveCodeForGenericPrompt() {
        let output = "Enter authentication code: "

        XCTAssertTrue(
            CLIAccountLoginCoordinator.outputRequestsInteractiveCode(output, provider: .gemini)
        )
    }

    func testOutputDoesNotRequestInteractiveCodeForRegularStatus() {
        let output = "Browser opened, complete the login..."

        XCTAssertFalse(
            CLIAccountLoginCoordinator.outputRequestsInteractiveCode(output, provider: .claude)
        )
    }
}
