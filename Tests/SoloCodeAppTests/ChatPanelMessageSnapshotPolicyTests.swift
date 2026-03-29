import XCTest
@testable import CoderIDE

final class ChatPanelMessageSnapshotPolicyTests: XCTestCase {
    func testPreservesNonEmptySnapshotWhileChromeIsBusy() {
        let conversationId = UUID()

        XCTAssertTrue(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 0,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 4,
                chromeBusy: true,
                lastBusyAt: nil,
                now: Date(timeIntervalSince1970: 10)
            )
        )
    }

    func testPreservesNonEmptySnapshotBrieflyAfterBusyEnds() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 20)

        XCTAssertTrue(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 0,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 6,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-0.35),
                now: now,
                idleGraceWindow: 0.75
            )
        )
    }

    func testDoesNotPreserveSnapshotAfterGraceWindowExpires() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 30)

        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 0,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 6,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-1.2),
                now: now,
                idleGraceWindow: 0.75
            )
        )
    }

    func testDoesNotPreserveWhenSnapshotBelongsToDifferentConversation() {
        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: UUID(),
                freshMessageCount: 0,
                previousSnapshotConversationId: UUID(),
                previousSnapshotMessageCount: 2,
                chromeBusy: true,
                lastBusyAt: Date()
            )
        )
    }

    // MARK: - Partial message count reduction (second message regression)

    func testPreservesSnapshotAgainstPartialMessageLossWhileBusy() {
        let conversationId = UUID()

        // Rust store returns 2 messages but snapshot has 4 (user1, assistant1, user2, assistant2)
        XCTAssertTrue(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 2,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 4,
                chromeBusy: true,
                lastBusyAt: nil,
                now: Date(timeIntervalSince1970: 10)
            )
        )
    }

    func testPreservesSnapshotAgainstPartialMessageLossInGraceWindow() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 20)

        XCTAssertTrue(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 1,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 3,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-0.5),
                now: now,
                idleGraceWindow: 0.75
            )
        )
    }

    func testDoesNotPreserveWhenMessageCountIncreases() {
        let conversationId = UUID()

        // Message count going UP is normal (new message added) — never preserve
        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 5,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 4,
                chromeBusy: true,
                lastBusyAt: Date()
            )
        )
    }

    func testDoesNotPreserveWhenMessageCountIsEqual() {
        let conversationId = UUID()

        // Same count: content changed, not message loss — let it through
        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 4,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 4,
                chromeBusy: true,
                lastBusyAt: Date()
            )
        )
    }

    func testDoesNotPreservePartialLossAfterGraceWindowExpires() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 30)

        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 2,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 4,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-1.2),
                now: now,
                idleGraceWindow: 0.75
            )
        )
    }

    /// Store vuoto transiente molti secondi dopo fine task (debug `2fa5b8`, ~22s).
    func testDefaultGracePreservesLongDelayedEmptyStoreAfterBusy() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 0,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 2,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-22),
                now: now
            )
        )
    }

    func testDefaultGraceStopsPreservingAfterThirtySeconds() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 300)

        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 0,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 2,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-35),
                now: now
            )
        )
    }

    func testDefaultGraceDoesNotPreserveLongDelayedPartialLossAfterBusy() {
        let conversationId = UUID()
        let now = Date(timeIntervalSince1970: 320)

        XCTAssertFalse(
            shouldPreserveSnapshotAgainstTransientEmptyStore(
                freshConversationId: conversationId,
                freshMessageCount: 1,
                previousSnapshotConversationId: conversationId,
                previousSnapshotMessageCount: 2,
                chromeBusy: false,
                lastBusyAt: now.addingTimeInterval(-22),
                now: now
            )
        )
    }
}
