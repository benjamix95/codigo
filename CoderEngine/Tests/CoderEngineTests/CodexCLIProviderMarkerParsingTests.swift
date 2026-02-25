import XCTest
@testable import CoderEngine

final class CodexCLIProviderMarkerParsingTests: XCTestCase {
    func testParseCoderIDEMarkerEventsMapsPolicyAckToRawEvent() {
        var carry = ""
        let events = CodexCLIProvider.parseCoderIDEMarkerEvents(
            in: "[CODERIDE:policy_ack|hash=xyz789]",
            carry: &carry
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "policy_ack")
        XCTAssertEqual(events.first?.payload["hash"], "xyz789")
        XCTAssertTrue(carry.isEmpty)
    }
}
