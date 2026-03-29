import XCTest
@testable import CoderIDE

final class ChatTurnInlineFileChangePreviewPolicyTests: XCTestCase {
    func testPreviewModeForFileChangeWithDiffIsExpandedOnly() {
        let change = makeChange(diffPreview: "@@ -1 +1 @@\n-old\n+new\n")

        XCTAssertEqual(
            ChatTurnInlineFileChangePreviewPolicy.mode(for: change),
            .expandedOnly
        )
    }

    func testPreviewModeForFileChangeWithoutDiffIsHidden() {
        let change = makeChange(diffPreview: nil)

        XCTAssertEqual(
            ChatTurnInlineFileChangePreviewPolicy.mode(for: change),
            .hidden
        )
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
            diffSource: diffPreview == nil ? .unknown : .payload,
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            isRunning: false
        )
    }
}
