import Foundation
import CoderEngine

extension ChatStore {
    func applyPlanCreate(
        goal: String,
        chosenPath: String?,
        steps: [PlanStepUpsertPayload],
        conversationId rawConversationId: String?
    ) {
        let explicitConversationId = parsedConversationId(rawConversationId)
        guard let conversationId = resolvePlanConversationId(preferred: explicitConversationId) else { return }
        var board = emptyPlanBoard()
        board.goal = normalizeText(goal, fallback: "Operational plan in progress")
        board.chosenPath = normalizeOptionalText(chosenPath)
        board.steps = steps.isEmpty ? board.steps : steps.map { planStep(from: $0) }
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }

    func applyPlanStepUpsert(
        _ payload: PlanStepUpsertPayload,
        fallbackConversationId: UUID?
    ) {
        guard let conversationId = resolvePlanConversationId(
            preferred: parsedConversationId(payload.conversationId) ?? fallbackConversationId
        ) else {
            return
        }
        var board = planBoards[conversationId] ?? emptyPlanBoard()
        upsertStep(
            in: &board,
            stepId: payload.stepId,
            status: payload.status,
            title: payload.title,
            description: payload.description,
            targetFile: payload.targetFile,
            linkedFiles: payload.linkedFiles,
            dependsOn: payload.dependsOn,
            notes: payload.notes
        )
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }

    func applyPlanStepBatchUpdate(
        items: [PlanStepBatchUpdateItemPayload],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        guard !items.isEmpty else { return }
        guard let conversationId = resolvePlanConversationId(
            preferred: parsedConversationId(rawConversationId) ?? fallbackConversationId
        ) else {
            return
        }

        var board = planBoards[conversationId] ?? emptyPlanBoard()
        for item in items {
            upsertStep(
                in: &board,
                stepId: item.stepId,
                status: item.status,
                title: item.title,
                description: item.description,
                targetFile: item.targetFile,
                linkedFiles: item.linkedFiles,
                dependsOn: item.dependsOn,
                notes: item.notes
            )
        }
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }

    func applyPlanStepReorder(
        orderedStepIds: [String],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        let orderedIds = orderedStepIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !orderedIds.isEmpty else { return }
        guard let conversationId = resolvePlanConversationId(
            preferred: parsedConversationId(rawConversationId) ?? fallbackConversationId
        ) else {
            return
        }

        var board = planBoards[conversationId] ?? emptyPlanBoard()
        let existingById = Dictionary(uniqueKeysWithValues: board.steps.map { ($0.id, $0) })

        var ordered: [PlanStep] = orderedIds.map { stepId in
            if let existing = existingById[stepId] {
                return existing
            }
            return PlanStep(
                id: stepId,
                title: "Step \(stepId)",
                description: "Step \(stepId)",
                targetFile: nil,
                status: .pending,
                updatedAt: .now
            )
        }

        let included = Set(orderedIds)
        let trailing = board.steps.filter { !included.contains($0.id) }
        ordered.append(contentsOf: trailing)
        board.steps = ordered
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }

    func applyPlanStepDependencySet(
        stepId: String,
        dependsOn: [String],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        let normalizedStepId = stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStepId.isEmpty else { return }
        guard let conversationId = resolvePlanConversationId(
            preferred: parsedConversationId(rawConversationId) ?? fallbackConversationId
        ) else {
            return
        }

        var board = planBoards[conversationId] ?? emptyPlanBoard()
        let existingStatus = board.steps.first(where: { $0.id == normalizedStepId })?.status ?? .pending
        upsertStep(
            in: &board,
            stepId: normalizedStepId,
            status: existingStatus,
            title: nil,
            description: nil,
            targetFile: nil,
            linkedFiles: nil,
            dependsOn: dependsOn,
            notes: nil
        )
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }

    func applyPlanSetWalkthrough(
        markdown: String,
        summary: String?,
        outcome: String,
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        let normalizedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMarkdown.isEmpty else { return }
        guard let conversationId = resolvePlanConversationId(
            preferred: parsedConversationId(rawConversationId) ?? fallbackConversationId
        ) else {
            return
        }

        var board = planBoards[conversationId] ?? emptyPlanBoard()
        board.walkthroughMarkdown = normalizedMarkdown
        board.walkthroughSummary = normalizeOptionalText(summary)
        board.walkthroughOutcome = normalizePlanOutcome(outcome)
        board.updatedAt = .now
        persistPlanBoard(board, for: conversationId)
    }
}

private extension ChatStore {
    func parsedConversationId(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    func normalizeText(_ raw: String?, fallback: String) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func normalizeOptionalText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizePlanOutcome(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "failed": return "failed"
        case "cancelled": return "cancelled"
        default: return "done"
        }
    }

    func emptyPlanBoard() -> PlanBoard {
        PlanBoard(
            goal: "Operational plan in progress",
            options: [],
            chosenPath: nil,
            steps: [],
            updatedAt: .now,
            walkthroughMarkdown: nil
        )
    }

    func planStep(from payload: PlanStepUpsertPayload) -> PlanStep {
        PlanStep(
            id: payload.stepId,
            title: normalizeText(payload.title, fallback: "Step \(payload.stepId)"),
            description: normalizeText(payload.description, fallback: payload.title ?? "Step \(payload.stepId)"),
            targetFile: normalizeOptionalText(payload.targetFile),
            status: payload.status,
            linkedFiles: payload.linkedFiles,
            dependsOn: payload.dependsOn,
            notes: normalizeOptionalText(payload.notes) ?? "",
            updatedAt: .now
        )
    }

    func upsertStep(
        in board: inout PlanBoard,
        stepId: String,
        status: PlanStepStatus,
        title: String?,
        description: String?,
        targetFile: String?,
        linkedFiles: [String]?,
        dependsOn: [String]?,
        notes: String?
    ) {
        let normalizedStepId = stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStepId.isEmpty else { return }

        if let index = board.steps.firstIndex(where: { $0.id == normalizedStepId }) {
            board.steps[index].status = status
            if let title = normalizeOptionalText(title) {
                board.steps[index].title = title
            }
            if let description = normalizeOptionalText(description) {
                board.steps[index].description = description
            }
            if let targetFile = normalizeOptionalText(targetFile) {
                board.steps[index].targetFile = targetFile
            }
            if let linkedFiles {
                board.steps[index].linkedFiles = linkedFiles
            }
            if let dependsOn {
                board.steps[index].dependsOn = dependsOn
            }
            if let notes = normalizeOptionalText(notes) {
                board.steps[index].notes = notes
            }
            board.steps[index].updatedAt = .now
            return
        }

        board.steps.append(
            PlanStep(
                id: normalizedStepId,
                title: normalizeText(title, fallback: "Step \(normalizedStepId)"),
                description: normalizeText(description, fallback: title ?? "Step \(normalizedStepId)"),
                targetFile: normalizeOptionalText(targetFile),
                status: status,
                linkedFiles: linkedFiles ?? [],
                dependsOn: dependsOn ?? [],
                notes: normalizeOptionalText(notes) ?? "",
                updatedAt: .now
            )
        )
    }
}
