import XCTest
@testable import CoderIDE

final class ActivityBarItemTests: XCTestCase {
    func testActivityBarItemExplorerExists() {
        let item = ActivityBarItem.explorer
        XCTAssertNotNil(item)
    }

    func testActivityBarItemSearchExists() {
        let item = ActivityBarItem.search
        XCTAssertNotNil(item)
    }

    func testActivityBarItemSourceControlExists() {
        let item = ActivityBarItem.sourceControl
        XCTAssertNotNil(item)
    }

    func testActivityBarItemSettingsExists() {
        let item = ActivityBarItem.settings
        XCTAssertNotNil(item)
    }

    func testActivityBarItemEquality() {
        XCTAssertEqual(ActivityBarItem.explorer, ActivityBarItem.explorer)
        XCTAssertNotEqual(ActivityBarItem.explorer, ActivityBarItem.search)
    }

    func testActivityBarItemsAreDistinct() {
        let items: [ActivityBarItem] = [.explorer, .search, .sourceControl, .settings]
        let unique = Set(items)
        XCTAssertEqual(unique.count, 4)
    }
}
