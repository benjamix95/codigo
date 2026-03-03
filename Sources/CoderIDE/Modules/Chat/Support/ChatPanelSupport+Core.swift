import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

enum CoderMode: String, CaseIterable {
    case agent = "Agent"
    case codeReviewMultiSwarm = "Code Review"
    case debug = "Debug"
    case plan = "Plan"
    case ide = "IDE"
    case browser = "Browser"
    case mcpServer = "MCP Server"
}

enum PlanningState: Equatable {
    case idle
    case awaitingClarification(questions: String)
    case awaitingChoice(planContent: String, options: [PlanOption])
}

enum PlanFlowPhase: Equatable {
    case idle
    case analyzing          // Phase 1: codebase analysis in progress
    case questioning        // Phase 2: generating/awaiting clarification questions
    case generating         // Phase 3: generating structured plan options
    case proposalReady
    case readyToBuild
    case building
}

enum ToolTraceTurnOutcome: Equatable {
    case success
    case failed
    case aborted
}

func toolTraceTurnOutcome(for flowState: ConversationFlowCoordinator.State) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    default:
        return .success
    }
}

func autoTodoFinalStatus(for outcome: ToolTraceTurnOutcome) -> TodoStatus {
    switch outcome {
    case .success:
        return .done
    case .failed, .aborted:
        return .blocked
    }
}

func rolloverAutoTodoOutcome(
    for flowState: ConversationFlowCoordinator.State,
    hasRunningOperations: Bool
) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    case .streaming:
        // A new turn started before the previous one reached completion.
        return .aborted
    case .idle, .completed:
        return hasRunningOperations ? .aborted : .success
    }
}

func todoIDsToAutoCompleteAfterSubagentBatch(
    todos: [TodoItem],
    conversationId: UUID? = nil,
    includePendingReviewTodo: Bool = false,
    reviewTodoTitle: String = "Code Review & Test"
) -> [UUID] {
    let normalizedReviewTitle = normalizedTodoTitle(reviewTodoTitle)
    let isInScope = todoConversationScopeFilter(todos: todos, conversationId: conversationId)
    var ids = Set(todos.filter { isInScope($0) && $0.source == .agent && $0.status == .inProgress }.map(\.id))
    if includePendingReviewTodo,
       let pendingReview = todos.first(where: {
           isInScope($0)
               && $0.source == .agent
               && $0.status == .pending
               && normalizedTodoTitle($0.title) == normalizedReviewTitle
       })
    {
        ids.insert(pendingReview.id)
    }
    return Array(ids)
}

func shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [String: String]) -> Bool {
    let roles = Set(
        (subagentBatchPayload["roles"] ?? "")
            .split(separator: ",")
            .map { normalizeRoleToken(String($0)) }
            .filter { !$0.isEmpty }
    )
    return roles.contains("reviewer") && roles.contains("testwriter")
}

func todoConversationScopeFilter(
    todos: [TodoItem],
    conversationId: UUID?
) -> (TodoItem) -> Bool {
    guard let conversationId else { return { _ in true } }
    let hasScoped = todos.contains { $0.planConversationId == conversationId }
    return { todo in
        if let scopedConversationId = todo.planConversationId {
            return scopedConversationId == conversationId
        }
        // Legacy fallback: keep unscoped todos visible when no scoped todo exists yet.
        return !hasScoped
    }
}

func traceEventsContainSuccessfulCodeEdits(_ traceEvents: [ToolTraceEvent]) -> Bool {
    traceEvents.contains(where: isSuccessfulFileMutationEvent(_:))
}

func touchedFilePathsFromTraceEvents(
    _ traceEvents: [ToolTraceEvent],
    maxCount: Int = 50
) -> [String] {
    let files = traceEvents.compactMap { event -> String? in
        guard isSuccessfulFileMutationEvent(event) else {
            return nil
        }
        let rawPath = (
            ToolTraceFileChangeMapper.from(event: event)?.path
                ?? event.payload["file"]
                ?? event.payload["path"]
                ?? event.payload["file_path"]
                ?? event.payload["relative_path"]
                ?? event.payload["target_path"]
                ?? ""
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }
        return normalizeTouchedFilePath(rawPath)
    }

    guard maxCount > 0 else { return [] }
    return Array(Set(files)).sorted().prefix(maxCount).map { $0 }
}

func normalizedTodoTitle(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func normalizeRoleToken(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .lowercased()
}

private func isSuccessfulMutationEventStatus(_ rawStatus: String?, isRunning: Bool) -> Bool {
    let normalized = (rawStatus ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalized.isEmpty {
        return !isRunning
    }
    return normalized == "completed"
        || normalized == "success"
        || normalized == "ok"
        || normalized == "done"
}

private func isSuccessfulFileMutationEvent(_ event: ToolTraceEvent) -> Bool {
    guard ToolTraceFileChangeMapper.isFileChangeEvent(event) else { return false }
    return isSuccessfulMutationEventStatus(event.payload["status"], isRunning: event.isRunning)
}

private func normalizeTouchedFilePath(_ rawPath: String) -> String {
    if let range = rawPath.range(of: "Sources/") { return String(rawPath[range.lowerBound...]) }
    if let range = rawPath.range(of: "Tests/") { return String(rawPath[range.lowerBound...]) }
    if let range = rawPath.range(of: "CoderEngine/") { return String(rawPath[range.lowerBound...]) }
    return (rawPath as NSString).lastPathComponent
}

func canExecutePlanBuild(phase: PlanFlowPhase, choice: String, allowIdleRebuild: Bool = false) -> Bool {
    let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if allowIdleRebuild, phase == .idle {
        return true
    }
    return phase == .proposalReady || phase == .readyToBuild
}

func normalizeBuildFinalResponse(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return text }
    let lines = trimmed.components(separatedBy: .newlines)
    let headerScan = lines.prefix(8).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let hasEarlyOptionHeader = headerScan.contains {
        $0.hasPrefix("## option")
    }
    let hasStrictOptions = !PlanOptionsParser.parseStrict(from: trimmed).isEmpty
    let checklistItems = lines.reduce(into: 0) { partialResult, line in
        if line.range(of: #"^\s*-\s*\[\s*.\s*\]\s+"#, options: .regularExpression) != nil {
            partialResult += 1
        }
    }
    let hasTodoHeader = lines.contains {
        $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## todo")
    }
    let looksLikePlanEcho = hasEarlyOptionHeader && hasStrictOptions && hasTodoHeader
        && checklistItems >= 1
    guard looksLikePlanEcho else { return text }
    var kept: [String] = []
    var skippingPlanBlock = false
    var inFence = false
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("```") {
            inFence.toggle()
            if !skippingPlanBlock {
                kept.append(line)
            }
            continue
        }
        if inFence {
            if !skippingPlanBlock {
                kept.append(line)
            }
            continue
        }
        let low = l.lowercased()
        if low.hasPrefix("## option") || low.hasPrefix("## todo") {
            skippingPlanBlock = true
            continue
        }
        if skippingPlanBlock && l.hasPrefix("##") {
            skippingPlanBlock = false
        }
        if !skippingPlanBlock {
            kept.append(line)
        }
    }
    let compact = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if compact.isEmpty {
        return text
    }
    return compact
}

func nextPlanFlowPhaseForOutput(
    fullText: String,
    current: PlanFlowPhase,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool
) -> PlanFlowPhase {
    let classification = PlanOutputClassifier.classify(
        fullText: fullText,
        current: current,
        coderMode: coderMode,
        shouldRunPlanInline: shouldRunPlanInline
    )
    return classification.isConfident ? classification.nextPhase : current
}
