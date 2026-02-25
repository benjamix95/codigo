import XCTest
@testable import CoderEngine

final class GeminiCLIProviderMarkerParsingTests: XCTestCase {
    func testParseCoderIDEMarkerEventsMapsDebugPanelToRawEvent() {
        var carry = ""
        let events = GeminiCLIProvider.parseCoderIDEMarkerEvents(
            in: "[CODERIDE:debug_panel|action=open|phase=analyzing]",
            carry: &carry
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "debug_panel_update")
        XCTAssertEqual(events.first?.payload["action"], "open")
        XCTAssertEqual(events.first?.payload["phase"], "analyzing")
        XCTAssertTrue(carry.isEmpty)
    }

    func testParseCoderIDEMarkerEventsMapsPolicyAckToRawEvent() {
        var carry = ""
        let events = GeminiCLIProvider.parseCoderIDEMarkerEvents(
            in: "[CODERIDE:policy_ack|hash=def456]",
            carry: &carry
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "policy_ack")
        XCTAssertEqual(events.first?.payload["hash"], "def456")
        XCTAssertTrue(carry.isEmpty)
    }
}
