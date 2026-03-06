import XCTest
@testable import CoderIDE

final class BrowserToolbarLayoutTests: XCTestCase {
    func testToolbarUsesCompactModeBelowCompactThreshold() {
        XCTAssertEqual(browserToolbarLayoutMode(for: 480), .compact)
    }

    func testToolbarUsesMediumModeBetweenThresholds() {
        XCTAssertEqual(browserToolbarLayoutMode(for: 620), .medium)
    }

    func testToolbarUsesFullModeOnWidePanels() {
        XCTAssertEqual(browserToolbarLayoutMode(for: 860), .full)
    }
}
