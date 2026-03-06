import XCTest
@testable import CoderIDE

@MainActor
final class EditorPanelsStoreTests: XCTestCase {
    func testQuickOpenTracksTargetPane() {
        let store = EditorPanelsStore()

        store.showQuickOpen(targetPane: .secondary)

        XCTAssertTrue(store.isQuickOpenVisible)
        XCTAssertEqual(store.quickOpenTargetPane, .secondary)
    }

    func testToggleBottomPanelClosesWhenRepeated() {
        let store = EditorPanelsStore()

        store.toggleBottomPanel(.problems)
        XCTAssertEqual(store.activeBottomPanel, .problems)

        store.toggleBottomPanel(.problems)
        XCTAssertNil(store.activeBottomPanel)
    }
}
