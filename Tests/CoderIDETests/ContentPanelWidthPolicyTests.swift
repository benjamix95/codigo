import XCTest
@testable import CoderIDE

final class ContentPanelWidthPolicyTests: XCTestCase {
    func testClampedWidthReturnsMinimumWhenStoredWidthIsZero() {
        let width = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: 0,
            detailWidth: 1200,
            fraction: 0.45
        )

        XCTAssertEqual(width, 300)
    }

    func testClampedWidthReturnsMinimumWhenStoredWidthIsNegative() {
        let width = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: -90,
            detailWidth: 1200,
            fraction: 0.45
        )

        XCTAssertEqual(width, 300)
    }

    func testClampedWidthReturnsMinimumWhenStoredWidthIsNotFinite() {
        let nanWidth = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: .nan,
            detailWidth: 1200,
            fraction: 0.45
        )
        let infiniteWidth = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: .infinity,
            detailWidth: 1200,
            fraction: 0.45
        )

        XCTAssertEqual(nanWidth, 300)
        XCTAssertEqual(infiniteWidth, 300)
    }

    func testClampedWidthCapsToMaximumFromDetailWidth() {
        let width = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: 900,
            detailWidth: 1000,
            fraction: 0.45
        )

        XCTAssertEqual(width, 450)
    }

    func testClampedWidthKeepsStoredValueWhenAlreadyWithinRange() {
        let width = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: 360,
            detailWidth: 1200,
            fraction: 0.45
        )

        XCTAssertEqual(width, 360)
    }

    func testMaxWidthFallsBackToMinimumWhenDetailWidthIsInvalid() {
        let zeroDetail = ContentPanelWidthPolicy.maxWidth(detailWidth: 0, fraction: 0.45)
        let nanDetail = ContentPanelWidthPolicy.maxWidth(detailWidth: .nan, fraction: 0.45)

        XCTAssertEqual(zeroDetail, 300)
        XCTAssertEqual(nanDetail, 300)
    }
}
