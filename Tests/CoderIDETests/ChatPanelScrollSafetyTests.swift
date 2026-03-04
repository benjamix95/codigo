import Foundation
import XCTest
@testable import CoderIDE

final class ChatPanelScrollSafetyTests: XCTestCase {
    func testCanScrollToTargetAcceptsTopAndBottomAnchors() {
        let messageIDs: Set<UUID> = []

        XCTAssertTrue(
            canScrollToTarget(
                AnyHashable("chat-scroll-top-anchor"),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: true,
                availableMessageIDs: messageIDs
            )
        )
        XCTAssertTrue(
            canScrollToTarget(
                AnyHashable("chat-scroll-bottom-anchor"),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: true,
                availableMessageIDs: messageIDs
            )
        )
    }

    func testCanScrollToTargetAcceptsKnownMessageID() {
        let knownID = UUID()
        let messageIDs: Set<UUID> = [knownID]

        XCTAssertTrue(
            canScrollToTarget(
                AnyHashable(knownID),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: true,
                availableMessageIDs: messageIDs
            )
        )
    }

    func testCanScrollToTargetRejectsUnknownTarget() {
        let unknownID = UUID()
        let messageIDs: Set<UUID> = []

        XCTAssertFalse(
            canScrollToTarget(
                AnyHashable(unknownID),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: true,
                availableMessageIDs: messageIDs
            )
        )
        XCTAssertFalse(
            canScrollToTarget(
                AnyHashable("plan-board"),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: true,
                availableMessageIDs: messageIDs
            )
        )
    }

    func testCanScrollToTargetRejectsAnchorWhenAnchorsNotAllowed() {
        let messageIDs: Set<UUID> = []

        XCTAssertFalse(
            canScrollToTarget(
                AnyHashable("chat-scroll-bottom-anchor"),
                topAnchorId: "chat-scroll-top-anchor",
                bottomAnchorId: "chat-scroll-bottom-anchor",
                allowAnchorTargets: false,
                availableMessageIDs: messageIDs
            )
        )
    }
}
