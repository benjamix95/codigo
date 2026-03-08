import XCTest
@testable import CoderIDE

final class MergeConflictParserTests: XCTestCase {
    func testResolveHunkKeepsLineAfterConflictBlock() {
        let content = [
            "line1",
            "<<<<<<< HEAD",
            "ours1",
            "=======",
            "theirs1",
            ">>>>>>> branch",
            "line_after",
            "line2"
        ].joined(separator: "\n")

        let parsed = MergeConflictParser.parse(content: content, filePath: "test.swift")
        guard let hunk = parsed.hunks.first else {
            XCTFail("Expected one conflict hunk")
            return
        }

        let resolved = MergeConflictParser.resolveHunk(content: content, hunk: hunk, resolution: .ours)

        XCTAssertEqual(
            resolved,
            ["line1", "ours1", "line_after", "line2"].joined(separator: "\n")
        )
    }
}
