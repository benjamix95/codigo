import Foundation
import SwiftUI

@MainActor
extension TaskActivityStore {
    func addActivity(_ activity: TaskActivity) {
        pendingActivities.append(activity)
        let isImmediate = activity.isRunning
            || pendingActivities.count >= 8
            || activity.type == "agent"
        if isImmediate {
            flushPendingActivities()
        } else {
            flushTask?.cancel()
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                self?.flushPendingActivities()
            }
        }
    }

    /// Flush any buffered activities synchronously. Useful in tests.
    func flushPending() {
        flushPendingActivities()
    }

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
        pruneExpiredInstantGreps(referenceDate: result.createdAt)

        // Deduplicate by normalized query + scope (case/space-insensitive).
        let normalizedQuery = result.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedScope = normalizedInstantGrepScope(result.scope)
        instantGreps.removeAll { existing in
            existing.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedQuery
                && normalizedInstantGrepScope(existing.scope) == normalizedScope
        }
        instantGreps.insert(result, at: 0)
        if instantGreps.count > instantGrepsHardCap {
            instantGreps = Array(instantGreps.prefix(instantGrepsHardCap))
        }
    }

    func configureInstantGrepRetention(maxItems: Int? = nil, ttlSeconds: TimeInterval? = nil) {
        if let maxItems {
            instantGrepsHardCap = max(1, maxItems)
        }
        if let ttlSeconds {
            instantGrepTTLSeconds = max(10, ttlSeconds)
        }
        pruneExpiredInstantGreps(referenceDate: Date())
        if instantGreps.count > instantGrepsHardCap {
            instantGreps = Array(instantGreps.prefix(instantGrepsHardCap))
        }
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
        let incomingConversationId = normalizedConversationId(activity)
        if let idx = activities.lastIndex(where: {
            $0.groupId == groupId
                && $0.type == activity.type
                && normalizedConversationId($0) == incomingConversationId
        }) {
            let existing = activities[idx]
            if shouldMerge(existing: existing, incoming: activity) {
                activities[idx] = activity
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
        ingestSwarmCard(activity: activity)
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

    private func normalizedConversationId(_ activity: TaskActivity) -> String {
        (activity.payload["conversation_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private func normalizedInstantGrepScope(_ scope: String) -> String {
        scope
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
    }

    private func pruneExpiredInstantGreps(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-instantGrepTTLSeconds)
        instantGreps.removeAll { $0.createdAt < cutoff }
    }

    func clear() {
        flushTask?.cancel()
        flushTask = nil
        pendingActivities.removeAll(keepingCapacity: true)
        activities.removeAll()
        instantGreps.removeAll()
        envelopes.removeAll()
        activeOperationsCount = 0
        unseenLiveEventsCount = 0
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        sortedSwarmCardsCache.removeAll()
        isSortedSwarmCardsCacheDirty = false
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
    }
}
