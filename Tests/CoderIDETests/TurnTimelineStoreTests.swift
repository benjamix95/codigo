import XCTest
@testable import CoderIDE

@MainActor
final class TurnTimelineStoreTests: XCTestCase {
    func testCommitTextHandlesShrinkWithoutLosingFutureChunks() {
        let store = TurnTimelineStore()

        store.commitText(from: "abcdef")
        store.commitText(from: "abc")
        store.commitText(from: "abcXYZ")

        let textChunks = store.segments.compactMap { segment -> String? in
            if case .assistantText(let text, _) = segment { return text }
            return nil
        }

        XCTAssertEqual(textChunks, ["abcdef", "XYZ"])
        XCTAssertNil(store.pendingStreamingChunk)
    }
}
