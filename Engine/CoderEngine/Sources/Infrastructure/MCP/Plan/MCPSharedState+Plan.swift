import Foundation

public extension MCPSharedState {
    static var planStateFilePath: URL {
        sharedDirectory.appendingPathComponent("plan_state.json")
    }

    static func writePlanSnapshotFromIDE(
        conversationId: UUID,
        goal: String,
        chosenPath: String?,
        steps: [[String: Any]],
        walkthroughMarkdown: String? = nil,
        summary: String? = nil,
        outcome: String? = nil,
        maxHistoryPerConversation: Int = 50
    ) {
        planFileAccessQueue.sync {
            ensurePlanDirectory()
            var document = _readPlanDocumentUnsafe()
            let now = isoTimestampNow()
            let conversationKey = normalizedConversationId(conversationId)
            let normalizedGoal = sanitizedText(goal, fallback: "Operational plan in progress")
            let normalizedChosenPath = optionalSanitizedText(chosenPath)
            let normalizedWalkthrough = optionalSanitizedText(walkthroughMarkdown)
            let normalizedSummary = optionalSanitizedText(summary)
            let normalizedOutcome = normalizeOutcome(outcome)
            let normalizedSteps = canonicalizedPlanSteps(steps, now: now)

            var history = document.snapshotsByConversation[conversationKey] ?? []
            let nextSnapshot = MCPSharedPlanSnapshot(
                snapshotId: UUID().uuidString.lowercased(),
                conversationId: conversationKey,
                goal: normalizedGoal,
                chosenPath: normalizedChosenPath,
                steps: normalizedSteps,
                walkthroughMarkdown: normalizedWalkthrough,
                summary: normalizedSummary,
                outcome: normalizedOutcome,
                createdAt: now,
                updatedAt: now
            )

            let nextSignature = signature(for: nextSnapshot)
            if let last = history.last, signature(for: last) == nextSignature {
                var updated = last
                updated.updatedAt = now
                history[history.count - 1] = updated
            } else {
                history.append(nextSnapshot)
            }

            let limit = max(1, maxHistoryPerConversation)
            if history.count > limit {
                history = Array(history.suffix(limit))
            }

            document.latestConversationId = conversationKey
            document.snapshotsByConversation[conversationKey] = history
            _writePlanDocumentUnsafe(document)
        }
    }

    static func readLatestPlanSnapshotJSONObject(
        conversationId: UUID?,
        includeHistory: Bool = false,
        historyLimit: Int = 10
    ) -> [String: Any]? {
        let document = readPlanDocument()
        guard let conversationKey = resolveConversationId(conversationId: conversationId, document: document),
              let history = document.snapshotsByConversation[conversationKey],
              let latest = history.last else {
            return nil
        }

        guard var latestObject = jsonObject(latest) else { return nil }
        latestObject["conversation_id"] = latest.conversationId
        latestObject["snapshot_id"] = latest.snapshotId

        var output: [String: Any] = [
            "version": document.version,
            "latest_conversation_id": document.latestConversationId as Any,
            "conversation_id": conversationKey,
            "snapshot": latestObject
        ]

        if includeHistory {
            let limit = max(1, min(historyLimit, 50))
            let recent = Array(history.suffix(limit))
            output["history"] = jsonArray(recent) ?? []
        }
        return output
    }

    static func readPlanHistoryJSONObject(
        conversationId: UUID?,
        limit: Int = 10
    ) -> [[String: Any]] {
        let document = readPlanDocument()
        guard let conversationKey = resolveConversationId(conversationId: conversationId, document: document),
              let history = document.snapshotsByConversation[conversationKey] else {
            return []
        }
        let effectiveLimit = max(1, min(limit, 50))
        let recent = Array(history.suffix(effectiveLimit))
        return jsonArray(recent) ?? []
    }

    static func readPlanDiffJSONObject(
        conversationId: UUID?,
        fromSnapshotId: String,
        toSnapshotId: String?
    ) -> [String: Any]? {
        let document = readPlanDocument()
        guard let resolved = resolveSnapshotsForDiff(
            conversationId: conversationId,
            fromSnapshotId: fromSnapshotId,
            toSnapshotId: toSnapshotId,
            document: document
        ) else {
            return nil
        }

        let fromById = Dictionary(
            resolved.from.steps.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let toById = Dictionary(
            resolved.to.steps.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let added = resolved.to.steps.filter { fromById[$0.id] == nil }
        let removed = resolved.from.steps.filter { toById[$0.id] == nil }
        let statusChanges: [MCPSharedPlanStatusChange] = resolved.to.steps.compactMap { step in
            guard let previous = fromById[step.id], previous.status != step.status else { return nil }
            return MCPSharedPlanStatusChange(
                stepId: step.id,
                title: step.title,
                fromStatus: previous.status,
                toStatus: step.status
            )
        }

        let diff = MCPSharedPlanDiffResult(
            fromSnapshotId: resolved.from.snapshotId,
            toSnapshotId: resolved.to.snapshotId,
            goalChanged: resolved.from.goal != resolved.to.goal,
            addedSteps: added,
            removedSteps: removed,
            statusChanges: statusChanges
        )
        guard let raw = jsonObject(diff) else { return nil }
        return [
            "from_snapshot_id": diff.fromSnapshotId,
            "to_snapshot_id": diff.toSnapshotId,
            "goal_changed": diff.goalChanged,
            "added_steps": raw["addedSteps"] ?? [],
            "removed_steps": raw["removedSteps"] ?? [],
            "status_changes": raw["statusChanges"] ?? [],
        ]
    }

    static func encodedPlanJSONObject(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

extension MCPSharedState {
    struct ResolvedPlanDiffSnapshots {
        let from: MCPSharedPlanSnapshot
        let to: MCPSharedPlanSnapshot
    }
}
