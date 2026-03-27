import Foundation
import os
import SwiftUI
import CoderEngine

@MainActor
final class TaskActivityStore: ObservableObject {
    // MARK: - Grouped Published State (25 → 3 structs)

    @Published var core = TaskActivityCoreState()
    @Published var swarm = TaskActivitySwarmState()
    @Published var codeReview = TaskActivityCodeReviewState()

    // MARK: - Backward-compatible accessors

    var activities: [TaskActivity] {
        get { core.activities }
        set { core.activities = newValue }
    }
    var instantGreps: [InstantGrepResult] {
        get { core.instantGreps }
        set { core.instantGreps = newValue }
    }
    var envelopes: [NormalizedEventEnvelope] {
        get { core.envelopes }
        set { core.envelopes = newValue }
    }
    var activeOperationsCount: Int {
        get { core.activeOperationsCount }
        set { core.activeOperationsCount = newValue }
    }
    var unseenLiveEventsCount: Int {
        get { core.unseenLiveEventsCount }
        set { core.unseenLiveEventsCount = newValue }
    }
    var swarmCards: [String: SwarmLiveCardState] {
        get { swarm.swarmCards }
        set { swarm.swarmCards = newValue }
    }
    var swarmEventsReceivedCount: Int {
        get { swarm.swarmEventsReceivedCount }
        set { swarm.swarmEventsReceivedCount = newValue }
    }
    var swarmEventsAssignedCount: Int {
        get { swarm.swarmEventsAssignedCount }
        set { swarm.swarmEventsAssignedCount = newValue }
    }
    var swarmEventsFallbackCount: Int {
        get { swarm.swarmEventsFallbackCount }
        set { swarm.swarmEventsFallbackCount = newValue }
    }
    var codeReviewFindings: [CodeReviewFinding] {
        get { codeReview.codeReviewFindings }
        set { codeReview.codeReviewFindings = newValue }
    }
    var codeReviewEvents: [CodeReviewSessionEvent] {
        get { codeReview.codeReviewEvents }
        set { codeReview.codeReviewEvents = newValue }
    }
    var codeReviewPhase: ReviewSessionPhase {
        get { codeReview.codeReviewPhase }
        set { codeReview.codeReviewPhase = newValue }
    }
    var codeReviewStage: ReviewSessionStage {
        get { codeReview.codeReviewStage }
        set { codeReview.codeReviewStage = newValue }
    }
    var codeReviewFindingsByConversation: [String: [CodeReviewFinding]] {
        get { codeReview.codeReviewFindingsByConversation }
        set { codeReview.codeReviewFindingsByConversation = newValue }
    }
    var codeReviewEventsByConversation: [String: [CodeReviewSessionEvent]] {
        get { codeReview.codeReviewEventsByConversation }
        set { codeReview.codeReviewEventsByConversation = newValue }
    }
    var codeReviewPhaseByConversation: [String: ReviewSessionPhase] {
        get { codeReview.codeReviewPhaseByConversation }
        set { codeReview.codeReviewPhaseByConversation = newValue }
    }
    var codeReviewSnapshotsBySession: [String: CodeReviewSessionSnapshot] {
        get { codeReview.codeReviewSnapshotsBySession }
        set { codeReview.codeReviewSnapshotsBySession = newValue }
    }
    var codeReviewSessionIdsByConversation: [String: [String]] {
        get { codeReview.codeReviewSessionIdsByConversation }
        set { codeReview.codeReviewSessionIdsByConversation = newValue }
    }
    var selectedCodeReviewSessionIdByConversation: [String: String] {
        get { codeReview.selectedCodeReviewSessionIdByConversation }
        set { codeReview.selectedCodeReviewSessionIdByConversation = newValue }
    }
    var verifiedFindingsEnvelopesBySession: [String: VerifiedFindingsSessionEnvelope] {
        get { codeReview.verifiedFindingsEnvelopesBySession }
        set { codeReview.verifiedFindingsEnvelopesBySession = newValue }
    }
    var verifiedFindingsProjectionsByConversation: [String: VerifiedFindingsProjectionSnapshot] {
        get { codeReview.verifiedFindingsProjectionsByConversation }
        set { codeReview.verifiedFindingsProjectionsByConversation = newValue }
    }
    var reviewPanelDerivedStateBySession: [String: ReviewPanelDerivedState] {
        get { codeReview.reviewPanelDerivedStateBySession }
        set { codeReview.reviewPanelDerivedStateBySession = newValue }
    }
    var reviewPanelDerivedStateByConversation: [String: ReviewPanelDerivedState] {
        get { codeReview.reviewPanelDerivedStateByConversation }
        set { codeReview.reviewPanelDerivedStateByConversation = newValue }
    }

    let swarmLogger = Logger(subsystem: "com.solocode.app", category: "swarm")
    let defaultSwarmEventsLimit = SwarmLiveReducer.defaultRecentEventsLimit
    let activitiesHardCap = 500
    var instantGrepsHardCap = 20
    var instantGrepTTLSeconds: TimeInterval = 12 * 60

    var pendingActivities: [TaskActivity] = []
    var flushTask: Task<Void, Never>?
    var swarmCardDedupKeys: [String: Set<String>] = [:]
    var sortedSwarmCardsCache: [SwarmLiveCardState] = []
    var scopedSwarmCardsCache: [String: [SwarmLiveCardState]] = [:]
    var isSortedSwarmCardsCacheDirty = true
    var pendingCodeReviewSnapshotsBySession: [String: (snapshot: CodeReviewSessionSnapshot, conversationId: UUID?)] = [:]
    var codeReviewSnapshotIngestTask: Task<Void, Never>?
    let codeReviewDerivationQueue = DispatchQueue(
        label: "com.solocode.task-activity.code-review-derivation",
        qos: .userInitiated
    )
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
        conversationId: UUID? = nil,
        uiCoalesceDelayNanoseconds: UInt64 = 8_000_000
    ) {
        pendingCodeReviewSnapshotsBySession[snapshot.sessionId] = (
            snapshot: snapshot,
            conversationId: conversationId
        )
        guard codeReviewSnapshotIngestTask == nil else { return }
        codeReviewSnapshotIngestTask = Task { [weak self] in
            if uiCoalesceDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: uiCoalesceDelayNanoseconds)
            }
            let pending = await MainActor.run { () -> [(snapshot: CodeReviewSessionSnapshot, conversationId: UUID?, existingEnvelope: VerifiedFindingsSessionEnvelope?)] in
                guard let self else { return [] }
                let pending = self.pendingCodeReviewSnapshotsBySession.values
                    .sorted {
                        if $0.snapshot.lastUpdatedAt != $1.snapshot.lastUpdatedAt {
                            return $0.snapshot.lastUpdatedAt < $1.snapshot.lastUpdatedAt
                        }
                        return $0.snapshot.mutationSequence < $1.snapshot.mutationSequence
                    }
                self.pendingCodeReviewSnapshotsBySession.removeAll()
                self.codeReviewSnapshotIngestTask = nil
                return pending.map { entry in
                    (
                        snapshot: entry.snapshot,
                        conversationId: entry.conversationId,
                        existingEnvelope: self.verifiedFindingsEnvelopesBySession[entry.snapshot.sessionId]
                    )
                }
            }
            guard let self, !pending.isEmpty else { return }
            self.codeReviewDerivationQueue.async { [weak self] in
                guard let self else { return }
                let prepared = pending.map { entry in
                    PreparedCodeReviewSnapshotIngest(
                        snapshot: entry.snapshot,
                        conversationId: entry.conversationId,
                        derivedState: ReviewPanelDerivedStateBuilder.build(
                            snapshot: entry.snapshot,
                            existingEnvelope: entry.existingEnvelope
                        )
                    )
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for entry in prepared {
                        self.ingestCodeReviewSnapshot(
                            entry.snapshot,
                            conversationId: entry.conversationId,
                            derivedState: entry.derivedState
                        )
                    }
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

private struct PreparedCodeReviewSnapshotIngest {
    let snapshot: CodeReviewSessionSnapshot
    let conversationId: UUID?
    let derivedState: ReviewPanelDerivedState
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

    /// Flush pending snapshots asynchronously. Safe to call from any context
    /// including @MainActor — never blocks the calling thread.
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.flushPendingSnapshotsLocked()
                continuation.resume()
            }
        }
    }

    /// Synchronous flush for use only from background/test contexts.
    /// Must NOT be called from the main thread — will deadlock if `queue` targets main.
    func flushSync() {
        queue.sync { [weak self] in
            self?.flushPendingSnapshotsLocked()
        }
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
