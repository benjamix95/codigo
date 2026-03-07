import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class CodeReviewPanelSessionScopingTests: XCTestCase {
    func testScopedReviewActivitiesForSessionFiltersMismatchedSession() {
        let activities = [
            TaskActivity(type: "review-worker-plan", title: "a", payload: ["session_id": "s1"]),
            TaskActivity(type: "review-worker-plan", title: "b", payload: ["session_id": "s2"]),
            TaskActivity(type: "review-worker-plan", title: "c", payload: [:]),
        ]

        let scoped = scopedReviewActivitiesForSession(activities, sessionId: "s1")
        XCTAssertEqual(scoped.map(\.title), ["a"])
    }

    func testReviewCardBelongsToSessionUsesRecentEvents() {
        let card = SwarmLiveCardState(
            swarmId: "worker-1",
            recentEvents: [
                TaskActivity(type: "agent", title: "s1", payload: ["session_id": "s1"]),
                TaskActivity(type: "agent", title: "s2", payload: ["session_id": "s2"]),
            ]
        )

        XCTAssertTrue(reviewCardBelongsToSession(card, sessionId: "s1"))
        XCTAssertFalse(reviewCardBelongsToSession(card, sessionId: "missing"))
    }

    func testCodeReviewSnapshotRejectsExplicitSessionFromDifferentConversation() {
        let store = TaskActivityStore()
        let conversationA = UUID()
        let conversationB = UUID()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-a",
            conversationId: conversationA,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: nil,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        store.ingestCodeReviewSnapshot(snapshot, conversationId: conversationA)

        let resolved = store.codeReviewSnapshot(
            sessionId: "session-a",
            conversationId: conversationB
        )

        XCTAssertNil(resolved)
    }
}
