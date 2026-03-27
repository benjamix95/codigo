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

    func testShouldShowLegacyChatTaskBarOnlyWhenComposerIsHiddenAndRuntimeIsBusy() {
        XCTAssertTrue(
            shouldShowLegacyChatTaskBar(
                shouldShowComposer: false,
                snapshotChromeLoading: true,
                isSummarizing: false
            )
        )
        XCTAssertTrue(
            shouldShowLegacyChatTaskBar(
                shouldShowComposer: false,
                snapshotChromeLoading: false,
                isSummarizing: true
            )
        )
        XCTAssertFalse(
            shouldShowLegacyChatTaskBar(
                shouldShowComposer: true,
                snapshotChromeLoading: true,
                isSummarizing: true
            )
        )
        XCTAssertFalse(
            shouldShowLegacyChatTaskBar(
                shouldShowComposer: false,
                snapshotChromeLoading: false,
                isSummarizing: false
            )
        )
    }

    func testBuildChatMessagesBarrierFingerprintIgnoresTraceChangesOutsideLatestMessage() {
        let conversationId = UUID()
        let firstMessage = ChatMessage(role: .user, content: "First")
        let lastMessage = ChatMessage(role: .assistant, content: "Second")
        let messages = [firstMessage, lastMessage]
        let oldFingerprint = buildChatMessagesBarrierFingerprint(
            conversationId: conversationId,
            messages: messages,
            traceEventsByMessageId: [
                firstMessage.id: [makeTraceEvent(conversationId: conversationId, assistantMessageId: firstMessage.id)]
            ],
            isLoading: false
        )
        let newFingerprint = buildChatMessagesBarrierFingerprint(
            conversationId: conversationId,
            messages: messages,
            traceEventsByMessageId: [
                firstMessage.id: [
                    makeTraceEvent(conversationId: conversationId, assistantMessageId: firstMessage.id),
                    makeTraceEvent(conversationId: conversationId, assistantMessageId: firstMessage.id),
                ]
            ],
            isLoading: false
        )

        XCTAssertEqual(oldFingerprint, newFingerprint)
    }

    func testBuildChatMessagesBarrierFingerprintChangesWhenLatestMessageTraceCountChanges() {
        let conversationId = UUID()
        let latestMessage = ChatMessage(role: .assistant, content: "Second")
        let messages = [ChatMessage(role: .user, content: "First"), latestMessage]
        let oldFingerprint = buildChatMessagesBarrierFingerprint(
            conversationId: conversationId,
            messages: messages,
            traceEventsByMessageId: [:],
            isLoading: true
        )
        let newFingerprint = buildChatMessagesBarrierFingerprint(
            conversationId: conversationId,
            messages: messages,
            traceEventsByMessageId: [
                latestMessage.id: [makeTraceEvent(conversationId: conversationId, assistantMessageId: latestMessage.id)]
            ],
            isLoading: true
        )

        XCTAssertNotEqual(oldFingerprint, newFingerprint)
    }

    private func makeTraceEvent(conversationId: UUID, assistantMessageId: UUID) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 0),
            providerId: "test",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            type: "bash",
            title: "Run",
            detail: nil,
            payload: [:],
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "tool_use"
        )
    }
}
