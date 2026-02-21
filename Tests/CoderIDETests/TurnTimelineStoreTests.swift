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

    func testAppendActivityRoutesThinkingAndToolPhases() {
        let store = TurnTimelineStore()

        let thinking = TaskActivity(
            type: "reasoning",
            title: "Ragionamento",
            phase: .thinking,
            isRunning: true
        )
        let tool = TaskActivity(
            type: "read_batch_started",
            title: "Read batch",
            phase: .editing,
            isRunning: true
        )

        store.appendActivity(thinking)
        store.appendActivity(tool)

        XCTAssertEqual(store.segments.count, 2)
        if case .thinking(let activity) = store.segments[0] {
            XCTAssertEqual(activity.type, "reasoning")
        } else {
            XCTFail("Il primo segmento deve essere thinking")
        }
        if case .tool(let activity) = store.segments[1] {
            XCTAssertEqual(activity.type, "read_batch_started")
        } else {
            XCTFail("Il secondo segmento deve essere tool")
        }
    }

    func testAppendTodoSnapshotIsUnique() {
        let store = TurnTimelineStore()

        store.appendTodoSnapshot()
        store.appendTodoSnapshot()
        store.appendTodoSnapshot()

        let todoCount = store.segments.filter {
            if case .todoSnapshot = $0 { return true }
            return false
        }.count
        XCTAssertEqual(todoCount, 1)
    }

    func testPendingStreamingChunkAndFinalizeFlow() {
        let store = TurnTimelineStore()

        store.updateLastKnownText("abc")
        XCTAssertEqual(store.pendingStreamingChunk, "abc")

        store.finalize(lastFullText: "abc")
        XCTAssertNil(store.pendingStreamingChunk)

        let textChunks = store.segments.compactMap { segment -> String? in
            if case .assistantText(let text, _) = segment { return text }
            return nil
        }
        XCTAssertEqual(textChunks, ["abc"])
    }
}
