import XCTest
@testable import CoderEngine

final class CodeReviewStreamTextAccumulatorTests: XCTestCase {
    func testConsumeResetsVisibleTextOnReplace() {
        var accumulator = CodeReviewStreamTextAccumulator()

        accumulator.consume(.textDelta("draft"))
        accumulator.consume(.textReplace("final"))
        accumulator.consume(.textDelta(" answer"))

        XCTAssertEqual(accumulator.text, "final answer")
    }

    func testConsumeIgnoresNonTextEvents() {
        var accumulator = CodeReviewStreamTextAccumulator()

        accumulator.consume(.started)
        accumulator.consume(.raw(type: "agent", payload: ["id": "1"]))
        accumulator.consume(.completed)

        XCTAssertTrue(accumulator.text.isEmpty)
    }
}
