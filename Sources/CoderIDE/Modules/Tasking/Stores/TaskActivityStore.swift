import Foundation
import os
import SwiftUI

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

    let swarmLogger = Logger(subsystem: "com.codigo.app", category: "swarm")
    let defaultSwarmEventsLimit = SwarmLiveReducer.defaultRecentEventsLimit
    let activitiesHardCap = 500

    var pendingActivities: [TaskActivity] = []
    var flushTask: Task<Void, Never>?
    var swarmCardDedupKeys: [String: Set<String>] = [:]
    var sortedSwarmCardsCache: [SwarmLiveCardState] = []
    var isSortedSwarmCardsCacheDirty = true

    init() { }

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
