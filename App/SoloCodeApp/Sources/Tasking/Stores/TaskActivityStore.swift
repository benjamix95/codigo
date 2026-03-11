import Foundation
import os
import SwiftUI
import CoderEngine

@MainActor
final class TaskActivityStore: ObservableObject {
    @Published var activities: [TaskActivity] = []
    @Published var instantGreps: [InstantGrepResult] = []
    @Published var envelopes: [NormalizedEventEnvelope] = []
    @Published var activeOperationsCount: Int = 0
    @Published var unseenLiveEventsCount: Int = 0
    @Published var swarmCards: [String: SwarmLiveCardState] = [:]
    @Published var swarmEventsReceivedCount: Int = 0
    @Published var swarmEventsAssignedCount: Int = 0
    @Published var swarmEventsFallbackCount: Int = 0

    // Code review session data (structured, from CodeReviewSessionSnapshot)
    @Published var codeReviewFindings: [CodeReviewFinding] = []
    @Published var codeReviewEvents: [CodeReviewSessionEvent] = []
    @Published var codeReviewPhase: ReviewSessionPhase = .idle
    @Published var codeReviewStage: ReviewSessionStage = .idle
    @Published var codeReviewFindingsByConversation: [String: [CodeReviewFinding]] = [:]
    @Published var codeReviewEventsByConversation: [String: [CodeReviewSessionEvent]] = [:]
    @Published var codeReviewPhaseByConversation: [String: ReviewSessionPhase] = [:]
    @Published var codeReviewSnapshotsBySession: [String: CodeReviewSessionSnapshot] = [:]
    @Published var codeReviewSessionIdsByConversation: [String: [String]] = [:]
    @Published var selectedCodeReviewSessionIdByConversation: [String: String] = [:]
    @Published var verifiedFindingsEnvelopesBySession: [String: VerifiedFindingsSessionEnvelope] = [:]
    @Published var verifiedFindingsProjectionsByConversation: [String: VerifiedFindingsProjectionSnapshot] = [:]
    @Published var reviewPanelDerivedStateBySession: [String: ReviewPanelDerivedState] = [:]
    @Published var reviewPanelDerivedStateByConversation: [String: ReviewPanelDerivedState] = [:]

    let swarmLogger = Logger(subsystem: "com.codigo.app", category: "swarm")
    let defaultSwarmEventsLimit = SwarmLiveReducer.defaultRecentEventsLimit
    let activitiesHardCap = 500
    var instantGrepsHardCap = 20
    var instantGrepTTLSeconds: TimeInterval = 12 * 60

    var pendingActivities: [TaskActivity] = []
    var flushTask: Task<Void, Never>?
    var swarmCardDedupKeys: [String: Set<String>] = [:]
    var sortedSwarmCardsCache: [SwarmLiveCardState] = []
    var isSortedSwarmCardsCacheDirty = true
    var pendingCodeReviewSnapshotsBySession: [String: (snapshot: CodeReviewSessionSnapshot, conversationId: UUID?)] = [:]
    var codeReviewSnapshotIngestTask: Task<Void, Never>?
    let persistenceBridge: TaskActivityPersistenceBridge

    init(
        persistenceBridge: TaskActivityPersistenceBridge = .shared
    ) {
        self.persistenceBridge = persistenceBridge
    }

    func scheduleDeferredMutation(
        _ mutation: @escaping @MainActor (TaskActivityStore) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            mutation(self)
        }
    }

    func scheduleCodeReviewSnapshotIngest(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID? = nil
    ) {
        pendingCodeReviewSnapshotsBySession[snapshot.sessionId] = (
            snapshot: snapshot,
            conversationId: conversationId
        )
        guard codeReviewSnapshotIngestTask == nil else { return }
        codeReviewSnapshotIngestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000)
            await MainActor.run {
                guard let self else { return }
                let pending = self.pendingCodeReviewSnapshotsBySession.values
                    .sorted {
                        if $0.snapshot.lastUpdatedAt != $1.snapshot.lastUpdatedAt {
                            return $0.snapshot.lastUpdatedAt < $1.snapshot.lastUpdatedAt
                        }
                        return $0.snapshot.mutationSequence < $1.snapshot.mutationSequence
                    }
                self.pendingCodeReviewSnapshotsBySession.removeAll()
                self.codeReviewSnapshotIngestTask = nil
                for entry in pending {
                    self.ingestCodeReviewSnapshot(
                        entry.snapshot,
                        conversationId: entry.conversationId
                    )
                }
            }
        }
    }

    func scheduleAddActivity(_ activity: TaskActivity) {
        scheduleDeferredMutation { store in
            store.addActivity(activity)
        }
    }

    func scheduleAppendOrMergeBatchEvent(_ activity: TaskActivity) {
        scheduleDeferredMutation { store in
            store.appendOrMergeBatchEvent(activity)
        }
    }

    func scheduleAddInstantGrep(_ result: InstantGrepResult) {
        scheduleDeferredMutation { store in
            store.addInstantGrep(result)
        }
    }

    func scheduleAddEnvelope(_ envelope: NormalizedEventEnvelope) {
        scheduleDeferredMutation { store in
            store.addEnvelope(envelope)
        }
    }

    func addEnvelope(_ envelope: NormalizedEventEnvelope) {
        envelopes.insert(envelope, at: 0)
        unseenLiveEventsCount += 1
        if envelopes.count > 50 {
            envelopes = Array(envelopes.prefix(50))
        }
    }

    func markPaused() {
        unseenLiveEventsCount += 1
    }

    func markResumed() {
        unseenLiveEventsCount += 1
    }

    func markLiveEventsSeen() {
        unseenLiveEventsCount = 0
    }

    func markPlanningAutoCompletedIfNeeded(reason: String = "todos_completed") {
        if let last = activities.last,
           last.type == "planning_auto_reset",
           last.payload["reason"] == reason {
            return
        }
        addActivity(
            TaskActivity(
                type: "planning_auto_reset",
                title: "Planning auto-completed",
                detail: "Active plan deactivated: no open todos and streaming finished",
                payload: [
                    "status": "completed",
                    "reason": reason,
                ],
                phase: .planning,
                isRunning: false
            )
        )
    }
}

final class TaskActivityPersistenceBridge: @unchecked Sendable {
    static let shared = TaskActivityPersistenceBridge()

    private let queue: DispatchQueue
    private let writeCodeReviewSnapshotImpl: @Sendable (CodeReviewSessionSnapshot) -> Void
    private let debounceInterval: TimeInterval
    private var pendingSnapshotsBySession: [String: CodeReviewSessionSnapshot] = [:]
    private var pendingFlushWorkItem: DispatchWorkItem?

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.solocode.task-activity.persistence",
            qos: .utility
        ),
        debounceInterval: TimeInterval = 0.15,
        writeCodeReviewSnapshot: @escaping @Sendable (CodeReviewSessionSnapshot) -> Void = {
            MCPSharedState.writeCodeReviewSnapshot($0)
        }
    ) {
        self.queue = queue
        self.debounceInterval = debounceInterval
        self.writeCodeReviewSnapshotImpl = writeCodeReviewSnapshot
    }

    func persistCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingSnapshotsBySession[snapshot.sessionId] = snapshot
            if snapshot.phase == .completed || snapshot.phase == .failed {
                self.flushPendingSnapshotsLocked()
                return
            }
            self.scheduleFlushLocked()
        }
    }

    func flush() {
        let group = DispatchGroup()
        group.enter()
        queue.async { [weak self] in
            self?.flushPendingSnapshotsLocked()
            group.leave()
        }
        group.wait()
    }

    private func scheduleFlushLocked() {
        pendingFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingSnapshotsLocked()
        }
        pendingFlushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushPendingSnapshotsLocked() {
        pendingFlushWorkItem?.cancel()
        pendingFlushWorkItem = nil
        let snapshots = pendingSnapshotsBySession.values.sorted {
            if $0.lastUpdatedAt != $1.lastUpdatedAt {
                return $0.lastUpdatedAt < $1.lastUpdatedAt
            }
            return $0.mutationSequence < $1.mutationSequence
        }
        pendingSnapshotsBySession.removeAll()
        for snapshot in snapshots {
            writeCodeReviewSnapshotImpl(snapshot)
        }
    }
}
