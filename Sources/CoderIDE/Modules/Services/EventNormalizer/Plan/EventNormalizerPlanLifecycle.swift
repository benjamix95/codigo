import Foundation

extension EventNormalizer {
    static let planLifecycleTypes: Set<String> = [
        "plan_create",
        "plan_read",
        "plan_step_upsert",
        "plan_step_batch_update",
        "plan_step_reorder",
        "plan_step_dependency_set",
        "plan_set_walkthrough",
        "plan_history_read",
        "plan_diff",
        "plan_request_user_input",
    ]

    static func isPlanLifecycleType(_ type: String) -> Bool {
        planLifecycleTypes.contains(type)
    }

    static func normalizePlanLifecycleEvent(
        type: String,
        payload: [String: String],
        timestamp: Date
    ) -> [NormalizedEvent] {
        switch type {
        case "plan_create":
            return normalizePlanCreate(payload: payload, timestamp: timestamp)
        case "plan_read":
            return normalizePlanRead(payload: payload, timestamp: timestamp)
        case "plan_step_upsert":
            return normalizePlanStepUpsert(payload: payload, timestamp: timestamp)
        case "plan_step_batch_update":
            return normalizePlanStepBatchUpdate(payload: payload, timestamp: timestamp)
        case "plan_step_reorder":
            return normalizePlanStepReorder(payload: payload, timestamp: timestamp)
        case "plan_step_dependency_set":
            return normalizePlanStepDependencySet(payload: payload, timestamp: timestamp)
        case "plan_set_walkthrough":
            return normalizePlanSetWalkthrough(payload: payload, timestamp: timestamp)
        case "plan_history_read":
            return normalizePlanHistoryRead(payload: payload, timestamp: timestamp)
        case "plan_diff":
            return normalizePlanDiff(payload: payload, timestamp: timestamp)
        case "plan_request_user_input":
            return normalizePlanRequestUserInput(payload: payload, timestamp: timestamp)
        default:
            return []
        }
    }

    private static func normalizePlanCreate(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let goal = payload["goal"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Operational plan in progress"
        let chosenPath = (payload["chosen_path"] ?? payload["chosenPath"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = normalizedConversationId(from: payload)
        let steps = parsePlanStepUpserts(from: payload["steps"])

        return [
            .planCreate(goal: goal, chosenPath: chosenPath, steps: steps, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_create",
                title: "Plan created",
                detail: goal,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanRead(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        return [
            .planRead(conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_read",
                title: "Plan read",
                detail: "Requested current plan snapshot",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanStepUpsert(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        guard let step = parseSinglePlanStepUpsert(payload: payload) else {
            return [invalidPlanPayloadActivity(type: "plan_step_upsert", payload: payload, timestamp: timestamp)]
        }
        let conversationId = normalizedConversationId(step.conversationId) ?? normalizedConversationId(from: payload)
        let normalizedStep = PlanStepUpsertPayload(
            stepId: step.stepId,
            status: step.status,
            title: step.title,
            description: step.description,
            targetFile: step.targetFile,
            linkedFiles: step.linkedFiles,
            dependsOn: step.dependsOn,
            notes: step.notes,
            conversationId: conversationId
        )

        return [
            .planStepUpsert(normalizedStep),
            .taskActivity(TaskActivity(
                type: "plan_step_upsert",
                title: normalizedStep.title ?? "Plan step upsert",
                detail: "Step \(normalizedStep.stepId) -> \(normalizedStep.status.rawValue)",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: normalizedStep.status == .running,
                groupId: conversationId ?? normalizedStep.stepId
            ))
        ]
    }

    private static func normalizePlanStepBatchUpdate(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        let items = parseBatchUpdateItems(from: payload["updates"])
        guard !items.isEmpty else {
            return [invalidPlanPayloadActivity(type: "plan_step_batch_update", payload: payload, timestamp: timestamp)]
        }
        return [
            .planStepBatchUpdate(items: items, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_step_batch_update",
                title: "Plan steps batch update",
                detail: "\(items.count) steps updated",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: items.contains(where: { $0.status == .running }),
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanStepReorder(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        let orderedIds = parseStringArray(raw: payload["ordered_step_ids"] ?? payload["orderedStepIds"])
        guard !orderedIds.isEmpty else {
            return [invalidPlanPayloadActivity(type: "plan_step_reorder", payload: payload, timestamp: timestamp)]
        }
        return [
            .planStepReorder(orderedStepIds: orderedIds, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_step_reorder",
                title: "Plan step order updated",
                detail: "\(orderedIds.count) ids",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanStepDependencySet(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        guard let stepId = (payload["step_id"] ?? payload["stepId"])?.trimmingCharacters(in: .whitespacesAndNewlines), !stepId.isEmpty else {
            return [invalidPlanPayloadActivity(type: "plan_step_dependency_set", payload: payload, timestamp: timestamp)]
        }
        let dependsOn = parseStringArray(raw: payload["depends_on"] ?? payload["dependsOn"])
        return [
            .planStepDependencySet(stepId: stepId, dependsOn: dependsOn, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_step_dependency_set",
                title: "Plan step dependencies updated",
                detail: "Step \(stepId)",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId ?? stepId
            ))
        ]
    }

    private static func normalizePlanSetWalkthrough(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        guard let markdown = payload["markdown"]?.trimmingCharacters(in: .whitespacesAndNewlines), !markdown.isEmpty else {
            return [invalidPlanPayloadActivity(type: "plan_set_walkthrough", payload: payload, timestamp: timestamp)]
        }
        let summary = payload["summary"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = normalizePlanOutcome(payload["outcome"])
        return [
            .planSetWalkthrough(markdown: markdown, summary: summary, outcome: outcome, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_set_walkthrough",
                title: "Plan walkthrough updated",
                detail: summary ?? outcome,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanHistoryRead(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let conversationId = normalizedConversationId(from: payload)
        let limit = Int(payload["limit"] ?? "")
        return [
            .planHistoryRead(conversationId: conversationId, limit: limit),
            .taskActivity(TaskActivity(
                type: "plan_history_read",
                title: "Plan history read",
                detail: "Requested plan snapshots history",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId
            ))
        ]
    }

    private static func normalizePlanDiff(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        guard let fromSnapshotId = (payload["from_snapshot_id"] ?? payload["fromSnapshotId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fromSnapshotId.isEmpty else {
            return [invalidPlanPayloadActivity(type: "plan_diff", payload: payload, timestamp: timestamp)]
        }
        let toSnapshotId = (payload["to_snapshot_id"] ?? payload["toSnapshotId"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = normalizedConversationId(from: payload)
        return [
            .planDiff(fromSnapshotId: fromSnapshotId, toSnapshotId: toSnapshotId, conversationId: conversationId),
            .taskActivity(TaskActivity(
                type: "plan_diff",
                title: "Plan diff computed",
                detail: "From \(fromSnapshotId)",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: conversationId ?? fromSnapshotId
            ))
        ]
    }

    private static func normalizePlanRequestUserInput(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        guard let request = parsePlanRequestUserInputPayload(payload: payload) else {
            return [invalidPlanPayloadActivity(type: "plan_request_user_input", payload: payload, timestamp: timestamp)]
        }

        let questionCount = request.questionnaire.questions.count
        let detail: String = {
            let phase = request.phase ?? "questioning"
            if let round = request.round {
                return "Round \(round) • \(questionCount) question(s) • \(phase)"
            }
            return "\(questionCount) question(s) • \(phase)"
        }()

        return [
            .planRequestUserInput(request),
            .taskActivity(TaskActivity(
                type: "plan_request_user_input",
                title: request.title ?? "Plan clarification requested",
                detail: request.context ?? detail,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false,
                groupId: request.conversationId
            ))
        ]
    }

    private static func normalizePlanOutcome(_ raw: String?) -> String {
        let normalized = (raw ?? "done").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "done", "failed", "cancelled": return normalized
        default: return "done"
        }
    }

    private static func normalizedConversationId(from payload: [String: String]) -> String? {
        normalizedConversationId(payload["conversation_id"] ?? payload["conversationId"])
    }

    private static func normalizedConversationId(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func invalidPlanPayloadActivity(type: String, payload: [String: String], timestamp: Date) -> NormalizedEvent {
        .taskActivity(TaskActivity(
            type: type,
            title: type,
            detail: "Invalid or missing plan payload",
            payload: payload,
            timestamp: timestamp,
            phase: .planning,
            isRunning: false
        ))
    }
}
