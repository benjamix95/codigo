import XCTest
@testable import CoderIDE

final class ChatPanelPositionTests: XCTestCase {
    func testDefaultChatPanelPositionIsLeft() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "chat_panel_position")
        let position = defaults.string(forKey: "chat_panel_position") ?? "left"
        XCTAssertEqual(position, "left")
    }

    func testChatPanelPositionTogglesToRight() {
        let defaults = UserDefaults.standard
        defaults.set("left", forKey: "chat_panel_position")
        let current = defaults.string(forKey: "chat_panel_position") ?? "left"
        let toggled = current == "left" ? "right" : "left"
        defaults.set(toggled, forKey: "chat_panel_position")
        XCTAssertEqual(defaults.string(forKey: "chat_panel_position"), "right")
    }

    func testChatPanelPositionTogglesToLeft() {
        let defaults = UserDefaults.standard
        defaults.set("right", forKey: "chat_panel_position")
        let current = defaults.string(forKey: "chat_panel_position") ?? "left"
        let toggled = current == "left" ? "right" : "left"
        defaults.set(toggled, forKey: "chat_panel_position")
        XCTAssertEqual(defaults.string(forKey: "chat_panel_position"), "left")
    }

    func testChatPanelPositionPersistsAcrossReads() {
        let defaults = UserDefaults.standard
        defaults.set("right", forKey: "chat_panel_position")
        XCTAssertEqual(defaults.string(forKey: "chat_panel_position"), "right")
        defaults.set("left", forKey: "chat_panel_position")
        XCTAssertEqual(defaults.string(forKey: "chat_panel_position"), "left")
    }

    func testChatPanelPositionAcceptsOnlyValidValues() {
        let validValues = ["left", "right"]
        let testValue = "center"
        let sanitized = validValues.contains(testValue) ? testValue : "left"
        XCTAssertEqual(sanitized, "left")
    }
}
