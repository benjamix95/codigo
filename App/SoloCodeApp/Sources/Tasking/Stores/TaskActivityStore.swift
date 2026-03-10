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
    let persistenceBridge: TaskActivityPersistenceBridge

    init(
        persistenceBridge: TaskActivityPersistenceBridge = .shared
    ) {
        self.persistenceBridge = persistenceBridge
    }

    func scheduleCodeReviewSnapshotIngest(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
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

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.solocode.task-activity.persistence",
            qos: .utility
        ),
        writeCodeReviewSnapshot: @escaping @Sendable (CodeReviewSessionSnapshot) -> Void = {
            MCPSharedState.writeCodeReviewSnapshot($0)
        }
    ) {
        self.queue = queue
        self.writeCodeReviewSnapshotImpl = writeCodeReviewSnapshot
    }

    func persistCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        queue.async { [writeCodeReviewSnapshotImpl] in
            writeCodeReviewSnapshotImpl(snapshot)
        }
    }

    func flush() {
        queue.sync {}
    }
}
