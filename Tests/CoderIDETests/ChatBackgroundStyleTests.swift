import XCTest
@testable import CoderIDE

final class ChatBackgroundStyleTests: XCTestCase {
    func testDefaultBackgroundStyleIsSolidNeutral() {
        XCTAssertEqual(ChatBackgroundStyle.defaultRawValue, ChatBackgroundStyle.solidNeutral.rawValue)
    }

    func testNormalizeBackgroundStyleFallsBackToSolidNeutral() {
        XCTAssertEqual(
            ChatBackgroundStyle.normalizedRawValue("unknown_style"),
            ChatBackgroundStyle.solidNeutral.rawValue
        )
    }

    func testNormalizeBackgroundStyleKeepsKnownValues() {
        XCTAssertEqual(
            ChatBackgroundStyle.normalizedRawValue(ChatBackgroundStyle.transparentLegacy.rawValue),
            ChatBackgroundStyle.transparentLegacy.rawValue
        )
        XCTAssertEqual(
            ChatBackgroundStyle.normalizedRawValue(ChatBackgroundStyle.solidNeutral.rawValue),
            ChatBackgroundStyle.solidNeutral.rawValue
        )
    }
}
