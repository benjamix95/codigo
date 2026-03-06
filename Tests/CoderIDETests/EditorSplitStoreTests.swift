import XCTest
@testable import CoderIDE

@MainActor
final class EditorSplitStoreTests: XCTestCase {
    func testToggleSplitSeedsSecondaryFromPrimary() {
        let store = EditorSplitStore()

        store.toggleSplit(using: "/tmp/main.swift")

        XCTAssertTrue(store.isSplitVisible)
        XCTAssertEqual(store.secondaryFilePath, "/tmp/main.swift")
        XCTAssertEqual(store.activePane, .secondary)
    }

    func testHandleClosedFileResetsSecondaryPane() {
        let store = EditorSplitStore()
        store.toggleSplit(using: "/tmp/main.swift")

        store.handleClosedFile("/tmp/main.swift")

        XCTAssertFalse(store.isSplitVisible)
        XCTAssertEqual(store.activePane, .primary)
    }
}
