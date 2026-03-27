import XCTest
@testable import CoderIDE

final class ConversationFlowStreamingPolicyTests: XCTestCase {
    func testTextFlushPolicyDefersTinyDirtyBufferUntilLatencyThreshold() {
        let policy = ConversationFlowTextFlushPolicy()
        let lastFlushAt = Date()

        XCTAssertFalse(
            policy.shouldFlushBeforeRawEvent(
                isDirty: true,
                renderedTextCount: 48,
                lastFlushedLength: 0,
                lastFlushAt: lastFlushAt,
                now: lastFlushAt.addingTimeInterval(0.02)
            )
        )
    }

    func testTextFlushPolicyFlushesWhenBufferedCharactersGrowPastThreshold() {
        let policy = ConversationFlowTextFlushPolicy()
        let lastFlushAt = Date()

        XCTAssertTrue(
            policy.shouldFlushBeforeRawEvent(
                isDirty: true,
                renderedTextCount: 256,
                lastFlushedLength: 0,
                lastFlushAt: lastFlushAt,
                now: lastFlushAt.addingTimeInterval(0.01)
            )
        )
    }

    func testRawEventBatchDrainPreservesOrderAndClearsBuffer() {
        var batch = ConversationFlowRawEventBatch()
        batch.append(("command_execution", ["id": "1"]))
        batch.append(("command_execution", ["id": "2"]))

        let drained = batch.drain()

        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained[0].0, "command_execution")
        XCTAssertEqual(drained[0].1["id"], "1")
        XCTAssertEqual(drained[1].1["id"], "2")
        XCTAssertTrue(batch.isEmpty)
    }
}
