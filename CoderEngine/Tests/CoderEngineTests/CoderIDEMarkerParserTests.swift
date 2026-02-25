import XCTest
@testable import CoderEngine

final class CoderIDEMarkerParserTests: XCTestCase {
    func testParseTreatsKeylessSegmentsAsContinuationOfPreviousValue() {
        let markers = CoderIDEMarkerParser.parse(
            from: "[CODERIDE:debug_panel|action=marker|phase=Sources/App.swift|42|added print]"
        )

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.kind, "debug_panel")
        XCTAssertEqual(markers.first?.payload["action"], "marker")
        XCTAssertEqual(
            markers.first?.payload["phase"],
            "Sources/App.swift|42|added print"
        )
    }

    func testParseStillSupportsEscapedPipeInValues() {
        let markers = CoderIDEMarkerParser.parse(
            from: #"[CODERIDE:tool_call|name=grep|query=foo\|bar]"#
        )

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.kind, "tool_call")
        XCTAssertEqual(markers.first?.payload["query"], "foo|bar")
    }
}
