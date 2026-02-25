import XCTest
@testable import CoderEngine

final class ClaudeCLIProviderMarkerParsingTests: XCTestCase {
    func testParseCoderIDEMarkerEventsMapsDebugPanelToRawEvent() {
        var carry = ""
        let events = ClaudeCLIProvider.parseCoderIDEMarkerEvents(
            in: "[CODERIDE:debug_panel|action=phase|phase=verifying]",
            carry: &carry
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "debug_panel_update")
        XCTAssertEqual(events.first?.payload["action"], "phase")
        XCTAssertEqual(events.first?.payload["phase"], "verifying")
        XCTAssertTrue(carry.isEmpty)
    }

    func testParseCoderIDEMarkerEventsMapsPolicyAckToRawEvent() {
        var carry = ""
        let events = ClaudeCLIProvider.parseCoderIDEMarkerEvents(
            in: "[CODERIDE:policy_ack|hash=abc123]",
            carry: &carry
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "policy_ack")
        XCTAssertEqual(events.first?.payload["hash"], "abc123")
        XCTAssertTrue(carry.isEmpty)
    }
}
