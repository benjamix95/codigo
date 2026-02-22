import XCTest
@testable import CoderIDE

final class ComposerRuntimeTimerTests: XCTestCase {
    func testBuildComposerFrozenTimerStateForManualStopAutoHides() {
        let state = buildComposerFrozenTimerState(elapsedSeconds: 95, endedByManualStop: true)
        XCTAssertEqual(state.text, "1:35")
        XCTAssertFalse(state.dismissible)
        XCTAssertEqual(state.autoHideDelay, 2.0)
    }

    func testBuildComposerFrozenTimerStateForNaturalCompletionIsDismissible() {
        let state = buildComposerFrozenTimerState(elapsedSeconds: 125, endedByManualStop: false)
        XCTAssertEqual(state.text, "2:05")
        XCTAssertTrue(state.dismissible)
        XCTAssertNil(state.autoHideDelay)
    }

    func testFormatComposerElapsedClampsNegativeValue() {
        XCTAssertEqual(formatComposerElapsed(-10), "0:00")
    }
}
