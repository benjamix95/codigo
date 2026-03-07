import XCTest
@testable import CoderIDE

final class SidebarThreadArchiveBehaviorTests: XCTestCase {
    func testSelectedArchivedThreadReselectsWhenThreadWouldDisappear() {
        XCTAssertTrue(
            shouldReselectAfterArchivingThread(
                wasSelected: true,
                archived: true,
                showArchived: false,
                isFavorite: false
            )
        )
    }

    func testSelectedArchivedFavoriteThreadDoesNotRequireReselection() {
        XCTAssertFalse(
            shouldReselectAfterArchivingThread(
                wasSelected: true,
                archived: true,
                showArchived: false,
                isFavorite: true
            )
        )
    }

    func testUnselectedOrRestoredThreadDoesNotRequireReselection() {
        XCTAssertFalse(
            shouldReselectAfterArchivingThread(
                wasSelected: false,
                archived: true,
                showArchived: false,
                isFavorite: false
            )
        )
        XCTAssertFalse(
            shouldReselectAfterArchivingThread(
                wasSelected: true,
                archived: false,
                showArchived: false,
                isFavorite: false
            )
        )
        XCTAssertFalse(
            shouldReselectAfterArchivingThread(
                wasSelected: true,
                archived: true,
                showArchived: true,
                isFavorite: false
            )
        )
    }
}
