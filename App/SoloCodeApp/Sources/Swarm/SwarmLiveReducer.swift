import Foundation

enum SwarmLiveReducer {
    static let defaultRecentEventsLimit = 80

    static func reduce(
        activities: [TaskActivity],
        limitRecentEvents: Int = defaultRecentEventsLimit
    ) -> [String: SwarmLiveCardState] {
        var cards: [String: SwarmLiveCardState] = [:]
        var dedupeKeys: [String: Set<String>] = [:]
        for activity in activities.sorted(by: { $0.timestamp < $1.timestamp }) {
            apply(
                activity: activity,
                to: &cards,
                dedupeKeys: &dedupeKeys,
                limitRecentEvents: max(1, limitRecentEvents)
            )
        }
        return cards
    }

    static func apply(
        activity: TaskActivity,
        to cards: inout [String: SwarmLiveCardState],
        dedupeKeys: inout [String: Set<String>],
        limitRecentEvents: Int = defaultRecentEventsLimit
    ) {
        let activity = canonicalize(activity, existingCards: cards)
        guard let owner = ownerSwarmId(for: activity, includeOrchestratorFallback: false) else {
            return
        }
        // Skip transient "queued" placeholders — they use temporary IDs
        // that won't match the real subagent started/completed events.
        if owner.hasPrefix("queued-") { return }

        var card = cards[owner] ?? SwarmLiveCardState(swarmId: owner)
        // Prefer readable_name for display, fallback to agent_name.
        // NEVER use raw swarm_id (owner) as display name.
        if let readableName = activity.payload["readable_name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !readableName.isEmpty {
            card.displayName = readableName
        } else if card.displayName.isEmpty,
                  let agentName = activity.payload["agent_name"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !agentName.isEmpty {
            card.displayName = agentName
        } else if card.displayName.isEmpty,
                  let displayName = bestDisplayName(for: activity),
                  !displayName.isEmpty {
            card.displayName = displayName
        } else if card.displayName.isEmpty {
            card.displayName = "Sub Agent"
        }
        // Populate roleType from event payload
        if card.roleType.isEmpty,
           let role = activity.payload["role"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !role.isEmpty {
            card.roleType = role
        }
        // Populate taskPrompt from event payload and inject as first transcript entry
        if card.taskPrompt.isEmpty,
           let task = activity.payload["task_summary"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !task.isEmpty {
            card.taskPrompt = task
            // Inject the task prompt as the FIRST entry in the chat transcript
            if let promptEntry = SubagentTranscriptEntry.userPrompt(task, timestamp: activity.timestamp) {
                card.transcript.insert(promptEntry, at: 0)
            }
        }
        let dedupeKey = dedupeKey(for: activity, owner: owner)
        var ownerKeys = dedupeKeys[owner] ?? Set<String>()
        let isDuplicate = ownerKeys.contains(dedupeKey)
        if !isDuplicate {
            ownerKeys.insert(dedupeKey)
            dedupeKeys[owner] = ownerKeys
            card.recentEvents.append(activity)
            if card.recentEvents.count > limitRecentEvents {
                card.recentEvents = Array(card.recentEvents.suffix(limitRecentEvents))
            }
            if let entry = transcriptEntry(for: activity) {
                card.transcript.append(entry)
                if card.transcript.count > SwarmLiveCardState.transcriptMaxEntries {
                    card.transcript = Array(card.transcript.suffix(SwarmLiveCardState.transcriptMaxEntries))
                }
            }
        }

        card.startedAt = card.startedAt ?? activity.timestamp
        card.lastEventAt = max(card.lastEventAt ?? .distantPast, activity.timestamp)
        if !activity.title.isEmpty {
            card.currentStepTitle = activity.title
        }

        if activity.type == "subagent_text", let text = activity.payload["text"], !text.isEmpty {
            let remaining = SwarmLiveCardState.liveTextMaxLength - card.liveText.count
            if remaining > 0 {
                card.liveText += String(text.prefix(remaining))
            }
        }

        if let detail = bestDetail(for: activity, displayName: card.displayName) {
            card.currentDetail = detail
        }
        if !isDuplicate {
            if activity.isRunning {
                card.activeOpsCount += 1
            } else if card.activeOpsCount > 0 {
                card.activeOpsCount -= 1
            }
            if isErrorEvent(activity) {
                card.errorCount += 1
            } else if isWarningEvent(activity) {
                card.warningCount += 1
            }
        }

        let transition = statusTransition(for: activity)
        switch transition {
        case .running:
            card.status = .running
            card.completedAt = nil
            card.summary = nil
            // Preserve errorCount across running transitions — errors from
            // previous phases should not be silently discarded when a card
            // re-enters running state (e.g. retry after failure).
            if card.isCollapsed {
                card.hasUnreadSinceCollapse = true
            }
        case .completed:
            card.status = .completed
            card.completedAt = activity.timestamp
            card.summary = summary(for: card.recentEvents)
            card.activeOpsCount = 0
            card.isCollapsed = true
            card.hasUnreadSinceCollapse = false
        case .failed:
            card.status = .failed
            card.activeOpsCount = 0
            if card.isCollapsed {
                card.hasUnreadSinceCollapse = true
            }
        case .none:
            if card.isCollapsed && !isDuplicate {
                card.hasUnreadSinceCollapse = true
            }
        }

        cards[owner] = card
    }

    static func sorted(states: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        states.sorted { lhs, rhs in
            let lw = sortWeight(lhs.status)
            let rw = sortWeight(rhs.status)
            if lw != rw { return lw < rw }
            return (lhs.lastEventAt ?? .distantPast) > (rhs.lastEventAt ?? .distantPast)
        }
    }

    private static func sortWeight(_ status: SwarmCardStatus) -> Int {
        switch status {
        case .running: return 0
        case .failed: return 1
        case .completed: return 2
        case .idle: return 3
        }
    }

    static func ownerSwarmId(
        for activity: TaskActivity,
        includeOrchestratorFallback: Bool
    ) -> String? {
        if let swarmId = SwarmMetadata.swarmId(from: activity.payload) {
            return swarmId
        }
        if includeOrchestratorFallback, SwarmMetadata.isSupervisorEvent(activity.payload) {
            return "orchestrator"
        }
        return nil
    }

    static func isSwarmCriticalTransition(_ activity: TaskActivity) -> Bool {
        guard ownerSwarmId(for: activity, includeOrchestratorFallback: false) != nil else {
            return false
        }
        switch normalizedLifecycleStatus(activity) {
        case .running, .completed, .failed:
            return true
        case .none:
            break
        }
        return isErrorEvent(activity)
    }

    private enum Transition {
        case running
        case completed
        case failed
        case none
    }

    private static func statusTransition(for activity: TaskActivity) -> Transition {
        if isErrorEvent(activity) { return .failed }
        switch normalizedLifecycleStatus(activity) {
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .running:
            return .running
        case .none:
            break
        }
        return .none
    }

}
