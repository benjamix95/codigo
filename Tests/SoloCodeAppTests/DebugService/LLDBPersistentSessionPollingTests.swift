import XCTest
@testable import CoderIDE

final class LLDBPersistentSessionPollingTests: XCTestCase {
    func testOutputPollingIntervalBacksOffAfterWarmStart() {
        XCTAssertEqual(lldbPersistentOutputPollIntervalNanoseconds(forAttempt: 0), 20_000_000)
        XCTAssertEqual(lldbPersistentOutputPollIntervalNanoseconds(forAttempt: 19), 20_000_000)
        XCTAssertEqual(lldbPersistentOutputPollIntervalNanoseconds(forAttempt: 20), 50_000_000)
        XCTAssertEqual(lldbPersistentOutputPollIntervalNanoseconds(forAttempt: 60), 100_000_000)
    }
}
