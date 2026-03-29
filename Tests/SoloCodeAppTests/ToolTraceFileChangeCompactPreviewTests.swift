import XCTest
@testable import CoderIDE

final class ToolTraceFileChangeCompactPreviewTests: XCTestCase {
    func testCompactPreviewTextStripsUnifiedDiffHeaders() {
        let change = makeChange(
            sequence: 1,
            diffPreview: """
            diff --git a/File.swift b/File.swift
            --- a/File.swift
            +++ b/File.swift
            @@ -1 +1 @@
            -let old = 1
            +let new = 2
            """,
            timestamp: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(change.compactPreviewText(limit: 2), "-let old = 1\n+let new = 2")
    }

    func testFullPreviewTextKeepsUnifiedDiffContentForExpandedCard() {
        let preview = """
        diff --git a/File.swift b/File.swift
        --- a/File.swift
        +++ b/File.swift
        @@ -1 +1 @@
        -let old = 1
        +let new = 2
        """
        let change = makeChange(
            sequence: 1,
            diffPreview: preview,
            timestamp: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(change.fullPreviewText, preview)
        XCTAssertTrue(change.hasFullPreview)
    }

    func testLatestPreviewableChangePrefersNewestSequence() {
        let older = makeChange(
            sequence: 1,
            diffPreview: "+old",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let newer = makeChange(
            sequence: 3,
            diffPreview: "+new",
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let withoutPreview = makeChange(
            sequence: 4,
            diffPreview: nil,
            timestamp: Date(timeIntervalSince1970: 4)
        )

        let picked = [older, withoutPreview, newer].latestPreviewableChange()

        XCTAssertEqual(picked?.sequence, 3)
        XCTAssertEqual(picked?.compactPreviewText(limit: 1), "+new")
    }

    private func makeChange(
        sequence: Int,
        diffPreview: String?,
        timestamp: Date
    ) -> ToolTraceFileChange {
        ToolTraceFileChange(
            eventId: UUID(),
            path: "App/SoloCodeApp/Sources/File.swift",
            basename: "File.swift",
            kind: .edited,
            added: 1,
            removed: 1,
            diffPreview: diffPreview,
            rawOutput: nil,
            diffSource: diffPreview == nil ? .unknown : .payload,
            sequence: sequence,
            timestamp: timestamp,
            isRunning: false
        )
    }
}
