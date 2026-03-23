import XCTest
import CoderEngine
@testable import CoderIDE

final class UsageFooterContextProgressTests: XCTestCase {
    func testFormatContextPercentLabelUsesOneDecimalBelowTenPercent() {
        XCTAssertEqual(formatContextPercentLabel(0), "0%")
        XCTAssertEqual(formatContextPercentLabel(0.003), "0.3%")
        XCTAssertEqual(formatContextPercentLabel(0.099), "9.9%")
        XCTAssertEqual(formatContextPercentLabel(0.10), "10%")
        XCTAssertEqual(formatContextPercentLabel(0.456), "46%")
    }

    func testFormatContextPercentHelpTextIsClampedAndStable() {
        XCTAssertEqual(formatContextPercentHelpText(-0.5), "Window context: 0.0% used")
        XCTAssertEqual(formatContextPercentHelpText(0.1234), "Window context: 12.3% used")
        XCTAssertEqual(formatContextPercentHelpText(1.5), "Window context: 100.0% used")
    }

    func testRenderedCircularProgressKeepsTinyProgressVisible() {
        XCTAssertEqual(renderedCircularProgress(-1), 0)
        XCTAssertEqual(renderedCircularProgress(0), 0)
        XCTAssertEqual(renderedCircularProgress(0.0004), 0.01)
        XCTAssertEqual(renderedCircularProgress(0.5), 0.5)
        XCTAssertEqual(renderedCircularProgress(2), 1)
    }

    func testCodebaseIndexProgressTextMatchesFooterContract() {
        let progress = IndexingProgress(current: 3, total: 4)
        XCTAssertEqual(codebaseIndexProgressText(progress), "75%")

        let emptyProgress = IndexingProgress(current: 0, total: 0)
        XCTAssertEqual(codebaseIndexProgressText(emptyProgress), "0%")
        XCTAssertNil(codebaseIndexProgressText(nil))
    }

    func testShouldShowFooterUsageDividerIncludesIndexProgressBranch() {
        XCTAssertFalse(
            shouldShowFooterUsageDivider(
                showProviderUsage: false,
                showContext: false,
                showTotal: false,
                indexProgress: nil
            )
        )

        XCTAssertTrue(
            shouldShowFooterUsageDivider(
                showProviderUsage: false,
                showContext: false,
                showTotal: false,
                indexProgress: IndexingProgress(current: 1, total: 4)
            )
        )
    }
}
