import XCTest
@testable import CoderIDE

final class LoginPollingBackoffTests: XCTestCase {
    func testBackoffStartsFromBaseAndRampsGradually() {
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 0, baseSeconds: 2, maxSeconds: 8), 2)
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 2, baseSeconds: 2, maxSeconds: 8), 2)
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 3, baseSeconds: 2, maxSeconds: 8), 3)
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 6, baseSeconds: 2, maxSeconds: 8), 4)
    }

    func testBackoffCapsAtConfiguredMaximum() {
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 99, baseSeconds: 2, maxSeconds: 8), 8)
        XCTAssertEqual(LoginPollingBackoff.seconds(forAttempt: 99, baseSeconds: 0, maxSeconds: 8), 0)
    }
}
