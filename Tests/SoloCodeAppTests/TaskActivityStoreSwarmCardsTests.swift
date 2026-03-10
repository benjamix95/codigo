import Combine
import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityStoreSwarmCardsTests: XCTestCase {
    func testIncrementalUpdatesAcrossParallelSwarmsAndFallbackOrchestrator() {
        let store = TaskActivityStore()

        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner",
                detail: "started",
                payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            ))
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Reviewer",
                detail: "started",
                payload: ["swarm_id": "reviewer", "group_id": "swarm-reviewer"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-reviewer"
            ))
        store.addActivity(
            TaskActivity(
                type: "web_search_started",
                title: "Search globale",
                detail: "started",
                payload: [:],
                phase: .searching,
                isRunning: true
            ))
        store.flushPending()

        let cards = store.swarmCardStates()
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "planner" }))
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "reviewer" }))
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "orchestrator" }))
    }

    func testSwarmIdsAndLaneFilteringUseGroupIdFallback() {
        let store = TaskActivityStore()

        store.addActivity(
            TaskActivity(
                type: "read_batch_started",
                title: "Group only read",
                detail: "started",
                payload: ["group_id": "swarm-reviewer"],
                phase: .editing,
                isRunning: true
            ))
        store.flushPending()

        XCTAssertEqual(store.swarmIds(), ["reviewer"])
        XCTAssertEqual(store.activities(forSwarmId: "reviewer").count, 1)

        let reviewerLane = store.activitiesForSwarmLane("reviewer")
        XCTAssertEqual(reviewerLane.count, 1)
        XCTAssertEqual(reviewerLane.first?.payload["group_id"], "swarm-reviewer")
    }

    func testAppendOrMergeBatchEventPreservesSwarmStartedAndCompleted() {
        let store = TaskActivityStore()
        let started = TaskActivity(
            type: "read_batch_started",
            title: "Read files",
            detail: "started",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "started"],
            phase: .editing,
            isRunning: true,
            groupId: "swarm-coder"
        )
        let completed = TaskActivity(
            type: "read_batch_started",
            title: "Read files",
            detail: "completed",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "completed"],
            phase: .editing,
            isRunning: false,
            groupId: "swarm-coder"
        )

        store.appendOrMergeBatchEvent(started)
        store.appendOrMergeBatchEvent(completed)
        store.flushPending()

        let card = store.swarmCardStates().first(where: { $0.swarmId == "coder" })
        XCTAssertNotNil(card)
        XCTAssertGreaterThanOrEqual(card?.recentEvents.count ?? 0, 2)
    }

    func testAppendOrMergeBatchEventHardCapPreservesRunningActivities() {
        let store = TaskActivityStore()
        let running = TaskActivity(
            type: "agent",
            title: "Long running operation",
            detail: "running",
            payload: ["status": "running"],
            phase: .planning,
            isRunning: true,
            groupId: "running-anchor"
        )
        store.appendOrMergeBatchEvent(running)

        for index in 0...store.activitiesHardCap {
            store.appendOrMergeBatchEvent(
                TaskActivity(
                    type: "batch_log",
                    title: "Log \(index)",
                    detail: "completed",
                    payload: ["status": "completed"],
                    phase: .planning,
                    isRunning: false,
                    groupId: "batch-\(index)"
                )
            )
        }

        XCTAssertEqual(store.activities.count, store.activitiesHardCap)
        XCTAssertTrue(store.activities.contains(where: { $0.id == running.id }))
    }

    func testScopedSwarmCardStatesContainOnlyScopedConversationEvents() {
        let store = TaskActivityStore()
        let conversationA = UUID()
        let conversationB = UUID()

        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner A",
                detail: "started",
                payload: [
                    "swarm_id": "planner",
                    "group_id": "swarm-planner",
                    "conversation_id": conversationA.uuidString.lowercased(),
                ],
                timestamp: Date(timeIntervalSince1970: 10),
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            )
        )
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner B",
                detail: "started",
                payload: [
                    "swarm_id": "planner",
                    "group_id": "swarm-planner",
                    "conversation_id": conversationB.uuidString.lowercased(),
                ],
                timestamp: Date(timeIntervalSince1970: 11),
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            )
        )
        store.flushPending()

        let scopedA = store.swarmCardStates(for: conversationA)
        XCTAssertEqual(scopedA.count, 1)
        XCTAssertEqual(scopedA[0].swarmId, "planner")
        XCTAssertTrue(scopedA[0].recentEvents.allSatisfy {
            canonicalConversationScope(from: $0.payload) == conversationA.uuidString.lowercased()
        })
    }

    func testSwarmCardStatesDoesNotPublishWhenReadFromView() {
        let store = TaskActivityStore()
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner",
                detail: "started",
                payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            )
        )
        store.flushPending()

        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        _ = store.swarmCardStates()

        XCTAssertEqual(publishCount, 0)
        XCTAssertTrue(store.isSortedSwarmCardsCacheDirty)
    }

    func testSwarmCardStatesIncludingPendingContainsBufferedActivitiesWithoutFlush() {
        let store = TaskActivityStore()
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner",
                detail: "started",
                payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            )
        )

        let cards = store.swarmCardStatesIncludingPending()

        XCTAssertEqual(cards.map(\.swarmId), ["planner"])
        XCTAssertEqual(cards.first?.status, .running)
    }

    func testFinalizedSwarmSnapshotAlsoFinalizesLiveStoreCards() async {
        let store = TaskActivityStore()
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner",
                detail: "started",
                payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            )
        )

        let cards = store.finalizedSwarmCardSnapshotForTaskCompletion()
        XCTAssertEqual(cards.map(\.status), [.completed])

        let drained = expectation(description: "drain main queue")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1.0)

        XCTAssertEqual(store.swarmCardStates().map(\.status), [.completed])
    }

    func testFinalizedSwarmSnapshotDoesNotFinalizeNextTurnCardsInSameConversation() async {
        let store = TaskActivityStore()
        let conversationId = UUID()
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner old turn",
                detail: "started",
                payload: [
                    "swarm_id": "planner-old",
                    "group_id": "swarm-planner-old",
                    "conversation_id": conversationId.uuidString.lowercased(),
                ],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner-old"
            )
        )

        let cards = store.finalizedSwarmCardSnapshotForTaskCompletion(for: conversationId)
        XCTAssertEqual(cards.map(\.swarmId), ["planner-old"])
        XCTAssertEqual(cards.map(\.status), [.completed])

        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner new turn",
                detail: "started",
                payload: [
                    "swarm_id": "planner-new",
                    "group_id": "swarm-planner-new",
                    "conversation_id": conversationId.uuidString.lowercased(),
                ],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner-new"
            )
        )

        let expectedStatuses: [String: SwarmCardStatus] = [
            "planner-old": .completed,
            "planner-new": .running,
        ]
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            let drained = expectation(description: "drain main queue")
            DispatchQueue.main.async {
                drained.fulfill()
            }
            await fulfillment(of: [drained], timeout: 1.0)

            let liveCards = store.swarmCardStates()
            let liveStatuses = Dictionary(uniqueKeysWithValues: liveCards.map { ($0.swarmId, $0.status) })
            if liveStatuses == expectedStatuses {
                return
            }
            await Task.yield()
        }
        let finalStatuses = Dictionary(
            uniqueKeysWithValues: store.swarmCardStates()
                .map { ($0.swarmId, $0.status) }
        )
        XCTAssertEqual(finalStatuses, expectedStatuses)
    }
}
