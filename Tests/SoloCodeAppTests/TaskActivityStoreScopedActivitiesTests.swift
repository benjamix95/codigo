import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class TaskActivityStoreScopedActivitiesTests: XCTestCase {
    func testActivitiesForConversationFiltersByConversationId() {
        let store = TaskActivityStore()
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        store.addActivity(makeActivity(type: "command_execution", conversationId: firstConversationId))
        store.addActivity(makeActivity(type: "command_execution", conversationId: secondConversationId))
        store.flushPending()

        let scoped = store.activities(for: firstConversationId)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.payload["conversation_id"], firstConversationId.uuidString.lowercased())
    }

    func testPlanRelevantRecentActivitiesForConversationIsScoped() {
        let store = TaskActivityStore()
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        store.addActivity(makeActivity(type: "plan_step_upsert", conversationId: firstConversationId))
        store.addActivity(makeActivity(type: "plan_step_upsert", conversationId: secondConversationId))
        store.flushPending()

        let scoped = store.planRelevantRecentActivities(limit: 20, conversationId: firstConversationId)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.payload["conversation_id"], firstConversationId.uuidString.lowercased())
    }

    func testActivitiesForConversationAcceptsCamelCaseConversationIdPayload() {
        let store = TaskActivityStore()
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        store.addActivity(makeActivity(type: "command_execution", conversationId: firstConversationId, useCamelCaseKey: true))
        store.addActivity(makeActivity(type: "command_execution", conversationId: secondConversationId, useCamelCaseKey: true))
        store.flushPending()

        let scoped = store.activities(for: firstConversationId)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.payload["conversationId"]?.lowercased(), firstConversationId.uuidString.lowercased())
    }

    func testIngestCodeReviewSnapshotDefersPersistenceOffMainThread() {
        let recorder = SnapshotRecorder()
        let bridge = TaskActivityPersistenceBridge(
            writeCodeReviewSnapshot: recorder.record(snapshot:)
        )
        let store = TaskActivityStore(persistenceBridge: bridge)
        let snapshot = makeSnapshot(sessionId: "session-async", mutationSequence: 1)

        store.ingestCodeReviewSnapshot(snapshot, conversationId: snapshot.conversationId)

        XCTAssertEqual(store.codeReviewSnapshotsBySession[snapshot.sessionId]?.sessionId, snapshot.sessionId)
        XCTAssertTrue(recorder.executedOnMainThread.allSatisfy { $0 == false })

        bridge.flush()

        XCTAssertEqual(recorder.snapshots.map(\.sessionId), [snapshot.sessionId])
        XCTAssertEqual(recorder.executedOnMainThread, [false])
    }

    func testPersistenceBridgePreservesSnapshotWriteOrder() {
        let recorder = SnapshotRecorder()
        let bridge = TaskActivityPersistenceBridge(
            writeCodeReviewSnapshot: recorder.record(snapshot:)
        )
        let store = TaskActivityStore(persistenceBridge: bridge)
        let conversationId = UUID()
        let first = makeSnapshot(
            sessionId: "session-ordered",
            conversationId: conversationId,
            mutationSequence: 1
        )
        let second = makeSnapshot(
            sessionId: "session-ordered",
            conversationId: conversationId,
            mutationSequence: 2
        )

        store.ingestCodeReviewSnapshot(first, conversationId: conversationId)
        store.ingestCodeReviewSnapshot(second, conversationId: conversationId)
        bridge.flush()

        XCTAssertEqual(recorder.snapshots.map(\.mutationSequence), [1, 2])
    }

    func testIngestCodeReviewSnapshotCachesFreshVerifiedEnvelopePerMutation() {
        let store = TaskActivityStore(
            persistenceBridge: TaskActivityPersistenceBridge(
                writeCodeReviewSnapshot: { _ in }
            )
        )
        let conversationId = UUID()
        let first = CodeReviewSessionSnapshot(
            sessionId: "session-verified-cache",
            conversationId: conversationId,
            mutationSequence: 1,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-old",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/App.swift",
                    lineNumber: 10,
                    endLineNumber: 10,
                    message: "Old finding",
                    status: .open
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let second = CodeReviewSessionSnapshot(
            sessionId: "session-verified-cache",
            conversationId: conversationId,
            mutationSequence: 2,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-new",
                    severity: .critical,
                    category: .security,
                    filePath: "Sources/Auth.swift",
                    lineNumber: 44,
                    endLineNumber: 44,
                    message: "New finding",
                    status: .open
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )

        store.ingestCodeReviewSnapshot(first, conversationId: conversationId)
        store.ingestCodeReviewSnapshot(second, conversationId: conversationId)

        let storedSnapshot = store.codeReviewSnapshot(
            sessionId: second.sessionId,
            conversationId: conversationId
        )
        let projection = store.verifiedFindingsProjection(for: conversationId)

        XCTAssertEqual(storedSnapshot?.mutationSequence, 2)
        XCTAssertEqual(storedSnapshot?.verifiedFindings?.projectionSnapshot.verifiedQueue.map(\.id), ["finding-new"])
        XCTAssertEqual(projection.verifiedQueue.map(\.id), ["finding-new"])
        XCTAssertEqual(store.verifiedFindingsEnvelopesBySession[second.sessionId]?.projectionSnapshot.verifiedQueue.map(\.id), ["finding-new"])
    }

    private func makeActivity(
        type: String,
        conversationId: UUID,
        useCamelCaseKey: Bool = false
    ) -> TaskActivity {
        let payload: [String: String] = useCamelCaseKey
            ? ["conversationId": conversationId.uuidString]
            : ["conversation_id": conversationId.uuidString.lowercased()]
        return TaskActivity(
            type: type,
            title: type,
            detail: nil,
            payload: payload,
            timestamp: Date(),
            phase: .planning,
            isRunning: false
        )
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID = UUID(),
        mutationSequence: UInt64
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence,
            phase: .analyzing,
            stage: .analysis,
            findings: [],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/App.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(mutationSequence))
        )
    }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshots: [CodeReviewSessionSnapshot] = []
    private var storedMainThreadFlags: [Bool] = []

    var snapshots: [CodeReviewSessionSnapshot] {
        lock.withLock { storedSnapshots }
    }

    var executedOnMainThread: [Bool] {
        lock.withLock { storedMainThreadFlags }
    }

    func record(snapshot: CodeReviewSessionSnapshot) {
        lock.withLock {
            storedSnapshots.append(snapshot)
            storedMainThreadFlags.append(Thread.isMainThread)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
