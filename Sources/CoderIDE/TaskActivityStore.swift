import SwiftUI

enum ActivityPhase: String, Codable {
    case thinking
    case editing
    case executing
    case searching
    case planning
}

/// Attività singola nel pannello task (Edit, Bash, Search, Agent role, ecc.)
struct TaskActivity: Identifiable {
    let id: UUID
    let type: String
    let title: String
    let detail: String?
    let payload: [String: String]
    let timestamp: Date
    let phase: ActivityPhase
    let isRunning: Bool
    let groupId: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        detail: String? = nil,
        payload: [String: String] = [:],
        timestamp: Date = .now,
        phase: ActivityPhase = .thinking,
        isRunning: Bool = true,
        groupId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.payload = payload
        self.timestamp = timestamp
        self.phase = phase
        self.isRunning = isRunning
        self.groupId = groupId
    }
}

enum SwarmLaneStatus: String, Sendable {
    case running
    case completed
    case failed
    case idle
}

struct SwarmLaneState: Identifiable, Sendable {
    let id: String
    let swarmId: String
    let status: SwarmLaneStatus
    let lastEventAt: Date?
    let currentActivityTitle: String
    let events: [TaskActivity]
    let activeOpsCount: Int
    let errorsCount: Int
    let hasUnreadWhileCollapsed: Bool
}

@MainActor
final class TaskActivityStore: ObservableObject {
    @Published private(set) var activities: [TaskActivity] = []
    @Published private(set) var instantGreps: [InstantGrepResult] = []
    @Published private(set) var envelopes: [NormalizedEventEnvelope] = []
    @Published private(set) var activeOperationsCount: Int = 0
    @Published private(set) var unseenLiveEventsCount: Int = 0
    @Published private(set) var swarmCards: [String: SwarmLiveCardState] = [:]
    @Published private(set) var swarmEventsReceivedCount: Int = 0
    @Published private(set) var swarmEventsAssignedCount: Int = 0
    @Published private(set) var swarmEventsFallbackCount: Int = 0

    private var swarmCardDedupKeys: [String: Set<String>] = [:]
    private let defaultSwarmEventsLimit = SwarmLiveReducer.defaultRecentEventsLimit

    func addActivity(_ activity: TaskActivity) {
        activities.append(activity)
        recalcActiveOperations()
        ingestSwarmCard(activity: activity)
    }

    func addInstantGrep(_ result: InstantGrepResult) {
        instantGreps.insert(result, at: 0)
        if instantGreps.count > 20 {
            instantGreps = Array(instantGreps.prefix(20))
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

    func appendOrMergeBatchEvent(_ activity: TaskActivity) {
        if shouldPreserveSwarmCriticalEvent(activity) {
            addActivity(activity)
            return
        }
        guard let groupId = activity.groupId else {
            addActivity(activity)
            return
        }
        if let idx = activities.lastIndex(where: { $0.groupId == groupId && $0.type == activity.type }) {
            let existing = activities[idx]
            if shouldMerge(existing: existing, incoming: activity) {
                activities[idx] = activity
            } else {
                activities.append(activity)
            }
        } else {
            activities.append(activity)
        }
        recalcActiveOperations()
        rebuildSwarmCards()
    }

    private func recalcActiveOperations() {
        activeOperationsCount = activities.suffix(40).filter(\.isRunning).count
    }

    private func shouldMerge(existing: TaskActivity, incoming: TaskActivity) -> Bool {
        if existing.groupId == nil || incoming.groupId == nil {
            return false
        }
        if existing.type != incoming.type {
            return false
        }
        let existingStatus = normalizedStatus(existing)
        let incomingStatus = normalizedStatus(incoming)
        if !existingStatus.isEmpty || !incomingStatus.isEmpty, existingStatus != incomingStatus {
            return false
        }
        let existingTerminal = isTerminalLike(existing)
        let incomingTerminal = isTerminalLike(incoming)
        if existingTerminal != incomingTerminal {
            return false
        }
        if existing.isRunning != incoming.isRunning, (!existing.isRunning || !incoming.isRunning) {
            return false
        }
        return true
    }

    private func normalizedStatus(_ activity: TaskActivity) -> String {
        let raw = (
            activity.payload["status"]
            ?? activity.payload["detail"]
            ?? activity.detail
            ?? ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        if raw.isEmpty { return "" }
        return raw.replacingOccurrences(of: "-", with: "_")
    }

    private func isTerminalLike(_ activity: TaskActivity) -> Bool {
        let status = normalizedStatus(activity)
        if status.contains("completed")
            || status.contains("failed")
            || status.contains("error")
            || status.contains("done")
            || status.contains("success")
        {
            return true
        }
        let title = activity.title.lowercased()
        let detail = (activity.detail ?? "").lowercased()
        return title.contains("completed")
            || title.contains("failed")
            || detail.contains("completed")
            || detail.contains("failed")
            || detail.contains("errore")
    }

    func clear() {
        activities.removeAll()
        instantGreps.removeAll()
        envelopes.removeAll()
        activeOperationsCount = 0
        unseenLiveEventsCount = 0
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
    }

    func shouldPreserveSwarmCriticalEvent(_ activity: TaskActivity) -> Bool {
        guard SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: false) != nil
        else {
            return false
        }
        return SwarmLiveReducer.isSwarmCriticalTransition(activity)
    }

    func setSwarmCardCollapsed(_ swarmId: String, collapsed: Bool) {
        guard var card = swarmCards[swarmId] else { return }
        card.isCollapsed = collapsed
        if !collapsed {
            card.hasUnreadSinceCollapse = false
        }
        swarmCards[swarmId] = card
    }

    func swarmCardStates(limitEventsPerCard: Int = SwarmLiveReducer.defaultRecentEventsLimit)
        -> [SwarmLiveCardState]
    {
        if limitEventsPerCard != defaultSwarmEventsLimit {
            let reduced = SwarmLiveReducer.reduce(
                activities: activities,
                limitRecentEvents: limitEventsPerCard
            )
            return SwarmLiveReducer.sorted(states: Array(reduced.values))
        }
        return SwarmLiveReducer.sorted(states: Array(swarmCards.values))
    }

    func recentActivities(limit: Int) -> [TaskActivity] {
        guard limit > 0 else { return [] }
        return Array(activities.suffix(limit))
    }

    func planRelevantRecentActivities(limit: Int = 60) -> [TaskActivity] {
        recentActivities(limit: limit).filter { activity in
            switch activity.type {
            case "command_execution", "bash",
                 "read_batch_started", "read_batch_completed",
                 "web_search", "web_search_started", "web_search_completed", "web_search_failed",
                 "mcp_tool_call",
                 "process_paused", "process_resumed",
                 "plan_step_update",
                 "file_change", "edit":
                return true
            default:
                return false
            }
        }
    }

    func swarmIds() -> [String] {
        let ids = activities.compactMap { $0.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(ids)).sorted()
    }

    func activities(forSwarmId swarmId: String, limit: Int = 80) -> [TaskActivity] {
        recentActivities(limit: max(limit, 1)).filter { $0.payload["swarm_id"] == swarmId }
    }

    func activitiesForSwarmLane(_ swarmId: String, limit: Int = 120) -> [TaskActivity] {
        let maxLimit = max(limit, 1)
        let sorted = activities.sorted { $0.timestamp < $1.timestamp }
        let direct = sorted.filter {
            $0.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) == swarmId
        }
        let correlated = sorted.filter {
            guard let groupId = $0.payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return groupId == "swarm-\(swarmId)"
        }
        var seen = Set<UUID>()
        let merged = (direct + correlated).filter { seen.insert($0.id).inserted }
        return Array(merged.suffix(maxLimit))
    }

    static func activitiesGroupedBySwarm(
        from activities: [TaskActivity],
        limitPerLane: Int = 120,
        includeCorrelatedGlobal: Bool = true
    ) -> [String: [TaskActivity]] {
        let effectiveLimit = max(1, limitPerLane)
        let sorted = activities.sorted { $0.timestamp < $1.timestamp }

        var grouped: [String: [TaskActivity]] = [:]
        for activity in sorted {
            guard let swarmId = activity.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !swarmId.isEmpty else { continue }
            grouped[swarmId, default: []].append(activity)
        }

        guard includeCorrelatedGlobal else {
            return grouped.mapValues { Array($0.suffix(effectiveLimit)) }
        }

        let correlated = correlatedGlobalActivities(from: sorted, swarmIds: Set(grouped.keys))
        for (swarmId, events) in correlated {
            var seen = Set(grouped[swarmId, default: []].map(\.id))
            for event in events where seen.insert(event.id).inserted {
                grouped[swarmId, default: []].append(event)
            }
        }

        return grouped.mapValues { events in
            Array(events.sorted { $0.timestamp < $1.timestamp }.suffix(effectiveLimit))
        }
    }

    static func correlatedGlobalActivities(
        from activities: [TaskActivity],
        swarmIds: Set<String>
    ) -> [String: [TaskActivity]] {
        guard !swarmIds.isEmpty else { return [:] }
        var out: [String: [TaskActivity]] = [:]
        for activity in activities {
            let hasDirectSwarm = !(activity.payload["swarm_id"] ?? "").isEmpty
            if hasDirectSwarm { continue }
            guard let groupId = activity.payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  groupId.hasPrefix("swarm-") else { continue }
            let swarmId = String(groupId.dropFirst("swarm-".count))
            guard swarmIds.contains(swarmId) else { continue }
            out[swarmId, default: []].append(activity)
        }
        return out
    }

    static func laneStates(
        from activities: [TaskActivity],
        limitPerLane: Int = 120
    ) -> [SwarmLaneState] {
        let cards = SwarmLiveReducer.reduce(activities: activities, limitRecentEvents: limitPerLane)
        var states: [SwarmLaneState] = cards.values.map { card in
            let status: SwarmLaneStatus = {
                switch card.status {
                case .running: return .running
                case .failed: return .failed
                case .completed: return .completed
                case .idle: return .idle
                }
            }()
            return SwarmLaneState(
                id: card.swarmId,
                swarmId: card.swarmId,
                status: status,
                lastEventAt: card.lastEventAt,
                currentActivityTitle: card.currentStepTitle,
                events: card.recentEvents,
                activeOpsCount: card.activeOpsCount,
                errorsCount: card.errorCount,
                hasUnreadWhileCollapsed: card.hasUnreadSinceCollapse
            )
        }
        return states.sorted { lhs, rhs in
            let lw = laneSortWeight(lhs.status)
            let rw = laneSortWeight(rhs.status)
            if lw != rw { return lw < rw }
            return (lhs.lastEventAt ?? .distantPast) > (rhs.lastEventAt ?? .distantPast)
        }
    }

    private static func laneSortWeight(_ status: SwarmLaneStatus) -> Int {
        switch status {
        case .running: return 0
        case .failed: return 1
        case .completed: return 2
        case .idle: return 3
        }
    }

    private static func laneStatus(for events: [TaskActivity]) -> SwarmLaneStatus {
        guard !events.isEmpty else { return .idle }
        if events.contains(where: \.isRunning) { return .running }
        if let last = events.last {
            if isErrorEvent(last) { return .failed }
            if let detail = last.payload["detail"]?.lowercased(), detail == "completed" { return .completed }
            if last.type == "agent", last.detail?.lowercased() == "completed" { return .completed }
        }
        if events.contains(where: isErrorEvent) { return .failed }
        return .completed
    }

    private static func isErrorEvent(_ activity: TaskActivity) -> Bool {
        if ["web_search_failed", "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied", "error"].contains(activity.type) {
            return true
        }
        let t = activity.title.lowercased()
        let d = (activity.detail ?? "").lowercased()
        return t.contains("errore") || t.contains("failed") || d.contains("errore") || d.contains("failed")
    }

    private func ingestSwarmCard(activity: TaskActivity) {
        swarmEventsReceivedCount += 1
        let owner = SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: true)
        if owner == "orchestrator" {
            swarmEventsFallbackCount += 1
        } else if owner != nil {
            swarmEventsAssignedCount += 1
        }
        SwarmLiveReducer.apply(
            activity: activity,
            to: &swarmCards,
            dedupeKeys: &swarmCardDedupKeys,
            limitRecentEvents: defaultSwarmEventsLimit
        )
    }

    private func rebuildSwarmCards() {
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
        for activity in activities {
            ingestSwarmCard(activity: activity)
        }
    }
}
