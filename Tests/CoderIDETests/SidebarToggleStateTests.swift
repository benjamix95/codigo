import XCTest
@testable import CoderIDE

final class SidebarToggleStateTests: XCTestCase {
    func testClosingVisibleSidebarReturnsNilSelection() {
        let next = SidebarToggleState.nextSelection(
            current: .sourceControl,
            lastVisible: .sourceControl
        )

        XCTAssertNil(next)
    }

    func testReopeningSidebarRestoresLastVisiblePanel() {
        let next = SidebarToggleState.nextSelection(
            current: nil,
            lastVisible: .search
        )

        XCTAssertEqual(next, .search)
    }

    func testReopeningSidebarFallsBackToExplorer() {
        let next = SidebarToggleState.nextSelection(
            current: nil,
            lastVisible: nil
        )

        XCTAssertEqual(next, .explorer)
    }

    func testRememberLastVisibleIgnoresNilAndSettings() {
        XCTAssertEqual(
            SidebarToggleState.updatedLastVisible(current: nil, previous: .explorer),
            .explorer
        )
        XCTAssertEqual(
            SidebarToggleState.updatedLastVisible(current: .settings, previous: .search),
            .search
        )
    }

    func testRememberLastVisibleUpdatesForSidebarPanels() {
        let updated = SidebarToggleState.updatedLastVisible(
            current: .sourceControl,
            previous: .explorer
        )

        XCTAssertEqual(updated, .sourceControl)
    }
}
