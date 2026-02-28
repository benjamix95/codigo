import os
import SwiftUI

enum ActivityPhase: String, Codable {
    case thinking
    case editing
    case executing
    case searching
    case planning
}

/// Single activity in the task panel (Edit, Bash, Search, Agent role, etc.)
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

    private let swarmLogger = Logger(subsystem: "com.codigo.app", category: "swarm")

    nonisolated private static let hiddenGenericTypes: Set<String> = [
        "reasoning",
        "thinking",
        "analysis",
        "deliberation",
        "turn_started",
        "turn_completed",
        "usage",
    ]

    nonisolated private static let hiddenGenericTypePrefixes: [String] = [
        "reasoning_",
        "thinking_",
        "analysis_",
        "trace_",
        "internal_",
        "usage_",
    ]

    nonisolated private static let concreteTypes: Set<String> = [
        "agent",
        "bash",
        "command_execution",
        "edit",
        "error",
        "file_change",
        "instant_grep",
        "mcp_tool_call",
        "permission_denied",
        "plan_step",
        "plan_step_update",
        "planning_auto_reset",
        "activate_plan_mode",
        "activate_debug_mode",
        "debug_phase_update",
        "debug_user_request",
        "debug_resolved",
        "debug_log",
        "debug_query",
        "debug_session",
        "debug_hypothesize",
        "debug_mark",
        "debug_clean",
        "process_paused",
        "process_resumed",
        "read_batch_started",
        "read_batch_completed",
        "review-worker-plan",
        "review-fix-round",
        "swarm_delegation_skipped",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "todo_read",
        "todo_write",
        "web_search",
        "web_search_started",
        "web_search_completed",
        "web_search_failed",
        "web_fetch",
        "web_fetch_started",
        "web_fetch_completed",
        "web_fetch_failed",
        "semantic_search",
        "read_lints",
        "debug_context",
        "skill_invocation",
    ]

    nonisolated static func isConcreteVisibleEventType(_ type: String) -> Bool {
        let normalized = normalizedEventType(type)
        if isHiddenGenericType(normalized) {
            return false
        }
        if concreteTypes.contains(normalized) {
            return true
        }
        if normalized.hasPrefix("web_search")
            || normalized.hasPrefix("web_fetch")
            || normalized.hasPrefix("todo_")
            || normalized.hasPrefix("read_batch")
            || normalized.hasPrefix("plan_step")
        {
            return true
        }
        return false
    }

    nonisolated static func isConcreteVisibleEvent(_ activity: TaskActivity) -> Bool {
        let normalized = normalizedEventType(activity.type)
        if isHiddenGenericType(normalized) {
            return false
        }
        if normalized == "mcp_tool_call" {
            return ToolTraceVisibility.isMCPEvent(activity: activity)
        }
        if isConcreteVisibleEventType(activity.type) {
            return true
        }
        // Fallback: unknown type with operational payload still qualifies as concrete.
        return !(activity.payload["command"] ?? "").isEmpty
            || !(activity.payload["path"] ?? "").isEmpty
            || !(activity.payload["file"] ?? "").isEmpty
            || !(activity.payload["query"] ?? "").isEmpty
            || !(activity.payload["tool"] ?? "").isEmpty
    }

    nonisolated private static func normalizedEventType(_ type: String) -> String {
        type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func isHiddenGenericType(_ normalizedType: String) -> Bool {
        if hiddenGenericTypes.contains(normalizedType) {
            return true
        }
        return hiddenGenericTypePrefixes.contains { normalizedType.hasPrefix($0) }
    }

    nonisolated static func lastConcreteVisibleActivity(in activities: [TaskActivity]) -> TaskActivity? {
        activities.last(where: isConcreteVisibleEvent(_:))
    }

    /// Last visible activity from the **main agent** only (excludes subagent events).
    nonisolated static func lastConcreteNonSwarmActivity(in activities: [TaskActivity]) -> TaskActivity? {
        activities.last { isConcreteVisibleEvent($0) && !SwarmMetadata.isSwarmEvent($0.payload) }
    }

    func concreteRecentActivities(limit: Int) -> [TaskActivity] {
        guard limit > 0 else { return [] }
        return activities.filter { Self.isConcreteVisibleEvent($0) }.suffix(limit).map { $0 }
    }

    nonisolated static func streamingStatusText(isPaused: Bool, activities: [TaskActivity]) -> String {
        if isPaused { return "Paused" }
        guard let last = lastConcreteNonSwarmActivity(in: activities)
                ?? lastConcreteVisibleActivity(in: activities) else {
            return "Thinking"
        }

        // When the last tool call completed, the model is deciding what to do next.
        // Show "Planning next move" only briefly — after a few seconds, switch to "Thinking"
        // so the status doesn't appear stuck while the model generates text or the next tool.
        if !last.isRunning {
            let elapsed = Date().timeIntervalSince(last.timestamp)
            if elapsed > 3 {
                return "Thinking"
            }
            return "Planning next move"
        }

        // Active tool call — show a specific label based on activity type
        let normalizedType = last.type.lowercased()
        if normalizedType.contains("read") || normalizedType.contains("glob") {
            return "Reading files"
        }
        if normalizedType.contains("grep") || normalizedType.contains("search") {
            return "Searching codebase"
        }
        if normalizedType.contains("edit") || normalizedType.contains("write") || normalizedType.contains("file_change") {
            return "Editing code"
        }
        if normalizedType.contains("bash") || normalizedType.contains("command") {
            return "Running command"
        }
        if normalizedType.contains("mcp") {
            return "Calling MCP tool"
        }
        if normalizedType.contains("web_search") {
            return "Searching web"
        }
        if normalizedType.contains("web_fetch") {
            return "Fetching page"
        }
        if normalizedType.hasPrefix("debug_") {
            return "Debugging"
        }
        if normalizedType.contains("todo") || normalizedType.contains("plan_step") {
            return "Planning next move"
        }
        switch last.phase {
        case .executing: return "Running"
        case .editing: return "Editing"
        case .searching: return "Searching"
        case .planning: return "Planning next move"
        case .thinking: return "Thinking"
        }
    }

    nonisolated static func streamingDetailText(
        activities: [TaskActivity],
        activeOperationsCount: Int
    ) -> String? {
        guard let last = lastConcreteVisibleActivity(in: activities) else { return nil }
        if activeOperationsCount > 1 {
            return "\(last.title) • \(activeOperationsCount) operations"
        }
        return last.title
    }

    private let activitiesHardCap = 500

    private var pendingActivities: [TaskActivity] = []
    private var flushTask: Task<Void, Never>?

    func addActivity(_ activity: TaskActivity) {
        pendingActivities.append(activity)
        // Flush immediately for important state changes, throttle others
        if activity.isRunning || pendingActivities.count >= 8 {
            flushPendingActivities()
        } else {
            flushTask?.cancel()
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                guard !Task.isCancelled else { return }
                self?.flushPendingActivities()
            }
        }
    }

    /// Flush any buffered activities synchronously. Useful in tests.
    func flushPending() { flushPendingActivities() }

    private func flushPendingActivities() {
        guard !pendingActivities.isEmpty else { return }
        flushTask?.cancel()
        flushTask = nil
        let batch = pendingActivities
        pendingActivities.removeAll(keepingCapacity: true)
        activities.append(contentsOf: batch)
        pruneCompletedTerminalActivities()
        if activities.count > activitiesHardCap {
            let excess = activities.count - activitiesHardCap
            var removed = 0
            activities.removeAll { act in
                guard removed < excess, !act.isRunning else { return false }
                removed += 1
                return true
            }
        }
        recalcActiveOperations()
        for activity in batch {
            ingestSwarmCard(activity: activity)
        }
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

    func appendOrMergeBatchEvent(_ activity: TaskActivity) {
        if shouldPreserveSwarmCriticalEvent(activity) {
            addActivity(activity)
            return
        }
        guard let groupId = activity.groupId else {
            addActivity(activity)
            return
        }
        var didMerge = false
        if let idx = activities.lastIndex(where: { $0.groupId == groupId && $0.type == activity.type }) {
            let existing = activities[idx]
            if shouldMerge(existing: existing, incoming: activity) {
                activities[idx] = activity
                didMerge = true
            } else {
                activities.append(activity)
            }
        } else {
            activities.append(activity)
        }
        pruneCompletedTerminalActivities()
        if activities.count > activitiesHardCap {
            let excess = activities.count - activitiesHardCap
            activities.removeFirst(excess)
        }
        recalcActiveOperations()
        if didMerge {
            rebuildSwarmCards()
        } else {
            ingestSwarmCard(activity: activity)
        }
    }

    private func pruneCompletedTerminalActivities() {
        let terminalTypes: Set<String> = ["command_execution", "bash"]
        var keepLatestCompletedId: UUID?
        for activity in activities.reversed() {
            if terminalTypes.contains(activity.type), !activity.isRunning {
                keepLatestCompletedId = activity.id
                break
            }
        }
        let cutoff = Date().addingTimeInterval(-8)
        activities.removeAll { activity in
            guard terminalTypes.contains(activity.type), !activity.isRunning else { return false }
            if activity.id == keepLatestCompletedId { return false }
            return activity.timestamp < cutoff
        }
    }

    private func recalcActiveOperations() {
        activeOperationsCount = activities.suffix(40)
            .filter { $0.isRunning && !SwarmMetadata.isSwarmEvent($0.payload) }
            .count
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
        if existing.isRunning != incoming.isRunning {
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
            || detail.contains("error")
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

    /// Resets swarm card state and rebuilds from existing activities.
    /// Used when switching conversations to refresh the swarm panel.
    /// Preserves the underlying activities so cards remain visible
    /// after task completion.
    func clearSwarmCards() {
        if swarmEventsReceivedCount > 0 {
            swarmLogger.debug("Swarm stats: received=\(self.swarmEventsReceivedCount) assigned=\(self.swarmEventsAssignedCount) fallback=\(self.swarmEventsFallbackCount) cards=\(self.swarmCards.count)")
        }
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
        // Rebuild cards from remaining activities so subagent cards
        // stay visible after the task completes.
        rebuildSwarmCards()
        // Bump counter so SwarmPanelView's onChange(of: liveChangeCount)
        // fires even when rebuild produces no events (e.g. new conversation).
        swarmEventsReceivedCount += 1
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
                 "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed",
                 "mcp_tool_call",
                 "process_paused", "process_resumed",
                 "plan_step", "plan_step_update", "planning_auto_reset",
                 "activate_plan_mode", "activate_debug_mode",
                 "debug_phase_update", "debug_user_request", "debug_resolved",
                 "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
                 "semantic_search", "read_lints", "debug_context",
                 "file_change", "edit":
                return true
            default:
                return false
            }
        }
    }

    func swarmIds() -> [String] {
        let ids = activities.compactMap { SwarmMetadata.swarmId(from: $0.payload) }
            .filter { !$0.isEmpty }
        return Array(Set(ids)).sorted()
    }

    func activities(forSwarmId swarmId: String, limit: Int = 80) -> [TaskActivity] {
        recentActivities(limit: max(limit, 1)).filter { SwarmMetadata.swarmId(from: $0.payload) == swarmId }
    }

    func activitiesForSwarmLane(_ swarmId: String, limit: Int = 120) -> [TaskActivity] {
        let maxLimit = max(limit, 1)
        let sorted = activities.sorted { $0.timestamp < $1.timestamp }
        let direct = sorted.filter {
            SwarmMetadata.swarmId(from: $0.payload) == swarmId
        }
        let correlated = sorted.filter {
            let directSwarmId = $0.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard directSwarmId.isEmpty,
                  let resolvedSwarmId = SwarmMetadata.swarmId(from: $0.payload),
                  resolvedSwarmId == swarmId else {
                return false
            }
            return true
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
            guard let swarmId = SwarmMetadata.swarmId(from: activity.payload), !swarmId.isEmpty else { continue }
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
            if let directSwarmId = activity.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !directSwarmId.isEmpty {
                continue
            }
            guard let swarmId = SwarmMetadata.swarmId(from: activity.payload) else { continue }
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
        let states: [SwarmLaneState] = cards.values.map { card in
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
        if ["web_search_failed", "web_fetch_failed", "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied", "error"].contains(activity.type) {
            return true
        }
        let status = (activity.payload["status"] ?? "").lowercased()
        return status == "failed" || status == "error"
    }

    private func ingestSwarmCard(activity: TaskActivity) {
        swarmEventsReceivedCount += 1
        let owner = SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: true)
        if owner == "orchestrator" {
            swarmEventsFallbackCount += 1
        } else if let o = owner {
            swarmEventsAssignedCount += 1
            swarmLogger.debug("Swarm event assigned to subagent '\(o)' type=\(activity.type) title=\(activity.title)")
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
