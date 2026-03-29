import XCTest
@testable import CoderIDE

final class ToolTraceFileChangeDiffLinesTests: XCTestCase {
    func testFullPreviewDiffLinesClassifyAdditionRemovalAndMetadata() {
        let change = makeChange(
            diffPreview: """
            diff --git a/File.swift b/File.swift
            --- a/File.swift
            +++ b/File.swift
            @@ -1 +1 @@
            -let old = 1
            +let new = 2
             let same = 3
            """
        )

        let lines = change.fullPreviewDiffLines()

        XCTAssertEqual(lines.map(\.style), [
            .metadata,
            .metadata,
            .metadata,
            .hunk,
            .removal,
            .addition,
            .context,
        ])
    }

    func testCompactPreviewDiffLinesReuseColorClassification() {
        let change = makeChange(
            diffPreview: """
            diff --git a/File.swift b/File.swift
            --- a/File.swift
            +++ b/File.swift
            @@ -1 +1 @@
            -let old = 1
            +let new = 2
            """
        )

        let lines = change.compactPreviewDiffLines(limit: 2)

        XCTAssertEqual(lines.map(\.text), ["-let old = 1", "+let new = 2"])
        XCTAssertEqual(lines.map(\.style), [.removal, .addition])
    }

    private func makeChange(diffPreview: String?) -> ToolTraceFileChange {
        ToolTraceFileChange(
            eventId: UUID(),
            path: "App/SoloCodeApp/Sources/File.swift",
            basename: "File.swift",
            kind: .edited,
            added: 1,
            removed: 1,
            diffPreview: diffPreview,
            rawOutput: nil,
            diffSource: .payload,
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            isRunning: false
        )
    }
}
