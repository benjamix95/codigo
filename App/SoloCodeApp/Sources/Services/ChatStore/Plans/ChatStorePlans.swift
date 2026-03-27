import Foundation
import CoderEngine

extension ChatStore {
func setPlanBoard(_ board: PlanBoard, for conversationId: UUID?) {
    guard let conversationId else { return }
    persistPlanBoard(board, for: conversationId)
}

func choosePlanPath(_ chosenPath: String, for conversationId: UUID?) {
    guard let conversationId else { return }
    let optionTodos = PlanOptionsParser.extractTodosFromOptionText(chosenPath)
    var board = planBoards[conversationId] ?? PlanBoard(
        goal: "Operational plan in progress",
        options: [],
        chosenPath: nil,
        steps: PlanBoard.buildSteps(fromTodoTitles: optionTodos),
        updatedAt: .now,
        walkthroughMarkdown: nil
    )
    board.chosenPath = chosenPath
    board.steps = PlanBoard.buildSteps(fromTodoTitles: optionTodos)
    board.updatedAt = .now
    persistPlanBoard(board, for: conversationId)
}

func planBoard(for conversationId: UUID?) -> PlanBoard? {
    guard let conversationId else { return nil }
    return planBoards[conversationId]
}

func attachPlanEntry(
    toMessageId messageId: UUID,
    conversationId: UUID?,
    entry: PlanHistoryEntry
) {
    guard let cidx = conversationIndex(for: conversationId) else { return }
    guard let midx = conversations[cidx].messages.firstIndex(where: { $0.id == messageId }) else { return }
    conversations[cidx].messages[midx].planAttachment = PlanAttachment(
        historyEntryId: entry.id,
        layoutVersion: 1,
        showExpand: true,
        snapshotTitle: entry.title
    )
    saveConversations()
}

@discardableResult
func attachPlanEntryToLastAssistant(
    conversationId: UUID?,
    entry: PlanHistoryEntry
) -> UUID? {
    guard let cidx = conversationIndex(for: conversationId) else { return nil }
    guard let midx = conversations[cidx].messages.lastIndex(where: { $0.role == .assistant }) else {
        return nil
    }
    let msgId = conversations[cidx].messages[midx].id
    conversations[cidx].messages[midx].planAttachment = PlanAttachment(
        historyEntryId: entry.id,
        layoutVersion: 1,
        showExpand: true,
        snapshotTitle: entry.title
    )
    saveConversations()
    return msgId
}

func backfillPlanAttachmentsIfNeeded(historyStore: PlanHistoryStore) {
    var changed = false
    for cidx in conversations.indices {
        let conv = conversations[cidx]
        for midx in conversations[cidx].messages.indices {
            var msg = conversations[cidx].messages[midx]
            guard msg.role == .assistant else { continue }
            if msg.planAttachment != nil { continue }
            let opts = PlanOptionsParser.parseStrict(from: msg.content)
            guard !opts.isEmpty else { continue }
            let normalizedHash = normalizedPlanContentHash(msg.content)
            let summary = PlanOptionsParser.extractDisplaySummary(from: msg.content)
            let existing = historyStore.findEntry(
                conversationId: conv.id,
                sourceMessageId: msg.id
            )
            let existingByHash = historyStore.entries.first(where: { entry in
                guard entry.conversationId == conv.id else { return false }
                guard entry.sourceMessageId == msg.id else { return false }
                return normalizedPlanContentHash(entry.markdown) == normalizedHash
            })
            let entry: PlanHistoryEntry
            if let existingByHash {
                entry = existingByHash
            } else if let existing {
                entry = existing
            } else {
                entry = historyStore.createEntry(
                    conversationId: conv.id,
                    contextId: conv.contextId,
                    contextFolderPath: conv.contextFolderPath,
                    title: summary.title,
                    markdown: msg.content,
                    options: opts,
                    chosenPath: nil,
                    tags: [],
                    sourceMessageId: msg.id
                )
            }
            msg.planAttachment = PlanAttachment(
                historyEntryId: entry.id,
                layoutVersion: 1,
                showExpand: true,
                snapshotTitle: entry.title
            )
            conversations[cidx].messages[midx] = msg
            changed = true
        }
    }
    if changed {
        saveConversations()
    }
}

/// Returns a deterministic hash for plan content deduplication.
/// Swift's `String.hashValue` is randomized per process, so it cannot be
/// used for cross-session comparison. We use a simple djb2 hash instead.
private func normalizedPlanContentHash(_ raw: String) -> Int {
    let normalized = raw
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .lowercased()
    var hash: UInt64 = 5381
    for byte in normalized.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return Int(bitPattern: UInt(hash))
}

private func canonicalPlanTitleKey(_ title: String) -> String {
    title
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
}

private func nextGeneratedPlanStepId(existing: [PlanStep]) -> String {
    let usedIds = Set(existing.map(\.id))
    var next = max(1, existing.compactMap { Int($0.id) }.max() ?? 0)
    while usedIds.contains(String(next)) {
        next += 1
    }
    return String(next)
}

func updatePlanStepStatus(stepId: String, status: PlanStepStatus, in conversationId: UUID?) {
    guard let conversationId, var board = planBoards[conversationId] else { return }
    guard let index = board.steps.firstIndex(where: { $0.id == stepId }) else { return }
    board.steps[index].status = status
    board.steps[index].updatedAt = .now
    board.updatedAt = .now
    persistPlanBoard(board, for: conversationId)
}

func syncPlanStepsFromCanonicalTodos(_ todos: [TodoItem], in conversationId: UUID?) {
    guard let conversationId else { return }
    var board = planBoards[conversationId] ?? PlanBoard(
        goal: "Operational plan in progress",
        options: [],
        chosenPath: nil,
        steps: [],
        updatedAt: .now,
        walkthroughMarkdown: nil
    )

    let canonicalTodos = todos
        .filter(\.isPlanCanonical)
        .sorted { lhs, rhs in
            let lhsOrder = lhs.planOrder ?? Int.max
            let rhsOrder = rhs.planOrder ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.createdAt < rhs.createdAt
        }

    // Don't replace steps with a placeholder when todos are empty —
    // this preserves existing step data during transient clear operations.
    guard !canonicalTodos.isEmpty else { return }

    // Merge into existing steps: update status for matched titles,
    // preserve existing step IDs and metadata (targetFile, description).
    var updatedSteps = board.steps
    var stepIndexByCanonicalKey: [String: Int] = [:]
    for (index, step) in updatedSteps.enumerated() {
        let key = canonicalPlanTitleKey(step.title)
        if !key.isEmpty, stepIndexByCanonicalKey[key] == nil {
            stepIndexByCanonicalKey[key] = index
        }
    }
    for todo in canonicalTodos {
        let todoStatus: PlanStepStatus = {
            switch todo.status {
            case .pending: return .pending
            case .inProgress: return .running
            case .done: return .done
            case .blocked: return .failed
            }
        }()
        let todoKey = canonicalPlanTitleKey(todo.title)
        if let idx = stepIndexByCanonicalKey[todoKey] {
            updatedSteps[idx].status = todoStatus
            updatedSteps[idx].updatedAt = .now
        } else {
            let nextStepId = nextGeneratedPlanStepId(existing: updatedSteps)
            updatedSteps.append(PlanStep(
                id: nextStepId,
                title: todo.title,
                description: todo.title,
                targetFile: nil,
                status: todoStatus
            ))
            stepIndexByCanonicalKey[todoKey] = updatedSteps.count - 1
        }
    }

    board.steps = updatedSteps
    board.updatedAt = .now
    persistPlanBoard(board, for: conversationId)
}

func upsertPlanStep(
    stepId: String,
    status: PlanStepStatus,
    title: String? = nil,
    in conversationId: UUID?
) {
    applyPlanStepUpsert(
        PlanStepUpsertPayload(
            stepId: stepId,
            status: status,
            title: title,
            description: title,
            targetFile: nil,
            linkedFiles: [],
            dependsOn: [],
            notes: nil,
            conversationId: nil
        ),
        fallbackConversationId: conversationId
    )
}

func setWalkthrough(_ markdown: String, for conversationId: UUID?) {
    applyPlanSetWalkthrough(
        markdown: markdown,
        summary: nil,
        outcome: "done",
        conversationId: nil,
        fallbackConversationId: conversationId
    )
}
}
