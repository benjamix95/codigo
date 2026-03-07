import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldResetTaskActivityStoreBeforeStartingTurn(
    activeTaskConversationIds: Set<UUID>,
    targetConversationId: UUID
) -> Bool {
    !activeTaskConversationIds.contains { $0 != targetConversationId }
}

enum PlanQuestionPhaseDecision: Equatable {
    case clarification(String)
    case proceedToGeneration
}

func hasNoQuestionsNeededSignal(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let withoutFenceDelimiters = trimmed.replacingOccurrences(
        of: #"(?m)^```[^\n]*$"#,
        with: " ",
        options: .regularExpression
    )
    let candidate = withoutFenceDelimiters
        .components(separatedBy: .newlines)
        .prefix(6)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard !candidate.isEmpty else { return false }
    return candidate.range(
        of: #"\bno[\s_\-]*questions[\s_\-]*needed\b"#,
        options: .regularExpression
    ) != nil
}

func decidePlanQuestionPhaseOutput(
    _ text: String,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool
) -> PlanQuestionPhaseDecision {
    if hasNoQuestionsNeededSignal(text) {
        return .proceedToGeneration
    }
    let classification = PlanOutputClassifier.classify(
        fullText: text,
        current: .questioning,
        coderMode: coderMode,
        shouldRunPlanInline: shouldRunPlanInline
    )
    if classification.isConfident, case .awaitingClarification(let questions) = classification.planningState {
        return .clarification(questions)
    }
    return .proceedToGeneration
}

func buildPlanClarificationPrompt(_ submission: PlanClarificationSubmission) -> String {
    let orderedAnswers = submission.answers.sorted(by: { $0.questionId < $1.questionId })
    let responseBody = orderedAnswers
        .map { answer in
            var lines: [String] = [
                "\(answer.questionId). \(answer.question)",
            ]
            if answer.optionIds.count > 1 {
                // Multi-select: list all selected options
                let selections = zip(answer.optionIds, answer.optionTexts)
                    .map { "\($0)) \($1)" }
                    .joined(separator: "; ")
                lines.append("   Selected answers: \(selections)")
            } else {
                lines.append("   Selected answer: \(answer.optionId)) \(answer.optionText)")
            }
            let custom = answer.customResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty {
                lines.append("   Custom response (overrides selection): \(custom)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")

    let finalNote = submission.finalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalNoteLine: String
    if finalNote.isEmpty {
        finalNoteLine = "Final user note: (omitted)"
    } else {
        finalNoteLine = "Final user note (optional): \(finalNote)"
    }
    return """
    Answers to plan clarification questions:
    \(responseBody)

    \(finalNoteLine)

    After these answers, run additional codebase analysis using the selected constraints.
    If new ambiguities appear, ask follow-up questions using `plan_request_user_input`.
    Propose the definitive plan (## Plan: Title + ## Todo) only when you are fully confident.
    """
}

func isPlanResumeBuild(canonicalTodos: [TodoItem]) -> Bool {
    guard !canonicalTodos.isEmpty else { return false }
    return canonicalTodos.contains(where: { $0.status == .done })
}

func buildPlanExecutionPrompt(
    workflowInstructions: String,
    executionPlanBase: String,
    planTodos: [String],
    canonicalTodos: [TodoItem]
) -> (prompt: String, isResume: Bool) {
    let isResume = isPlanResumeBuild(canonicalTodos: canonicalTodos)
    if isResume {
        let sortedPlanTodos = canonicalTodos.sorted { lhs, rhs in
            if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
            return lhs.updatedAt < rhs.updatedAt
        }
        let doneList = sortedPlanTodos
            .filter { $0.status == .done }
            .map { "- [x] \($0.title)" }
            .joined(separator: "\n")
        let pendingList = sortedPlanTodos
            .filter { $0.status != .done }
            .map { "- [ ] \($0.title)" }
            .joined(separator: "\n")
        let prompt = """
        \(workflowInstructions)

        **IMPLEMENTATION RESUME** - Continue from where you left off.

        \(executionPlanBase)

        **Already completed todos:** Verify the corresponding file changes are present. If missing or reverted, re-apply them.
        \(doneList.isEmpty ? "(none)" : doneList)

        **Remaining todos:**
        \(pendingList.isEmpty ? "(all completed)" : pendingList)

        Proceed by validating completed tasks, restoring any missing ones, then finishing the remaining tasks.
        """
        return (prompt, true)
    }

    var prompt = "\(workflowInstructions)\n\nThe user selected a plan option. Implement it by following TODOs EXACTLY in order. TODOs are mandatory: do not deviate, skip, or reorder.\n\n\(executionPlanBase)"
    if !planTodos.isEmpty {
        let todoList = planTodos.enumerated().map { "\($0.offset + 1). [ ] \($0.element)" }.joined(separator: "\n")
        prompt += "\n\n**MANDATORY TODOs (follow in order, complete ALL):**\n\(todoList)\n\nREMINDER: each TODO must go pending -> in_progress -> done. Do not finish until all are done."
    }
    return (prompt, false)
}

func shouldFallbackToPreferredProvider(
    selectedProviderIsAuthenticated: Bool,
    hasPreferredAuthenticatedFallback: Bool
) -> Bool {
    !selectedProviderIsAuthenticated && hasPreferredAuthenticatedFallback
}

func shouldSyncModeOnProviderChange(suppressForUserPicker: Bool) -> Bool {
    !suppressForUserPicker
}

func shouldShowSwarmViewOnly(for mode: CoderMode) -> Bool {
    false
}

func shouldShowComposer(for mode: CoderMode) -> Bool {
    !shouldShowSwarmViewOnly(for: mode)
}

func shouldShowUsageFooter(for mode: CoderMode) -> Bool {
    mode != .ide
}

func shouldEnableTaskPanelForMode(_ mode: CoderMode) -> Bool {
    switch mode {
    case .agent, .debug, .plan, .codeReviewMultiSwarm, .browser:
        return true
    case .ide, .mcpServer:
        return false
    }
}

func shouldAutoOpenSwarmPanelForEvent(eventConversationId: UUID?, selectedConversationId: UUID?) -> Bool {
    guard let selectedConversationId else { return false }
    guard let eventConversationId else { return true }
    return eventConversationId == selectedConversationId
}

func shouldStartDebugSessionOnAutoActivate(currentPhase: DebugFlowPhase) -> Bool {
    switch currentPhase {
    case .idle, .resolved:
        return true
    case .describing, .reproducing, .fixing, .instrumenting, .verifying:
        return false
    }
}

func resolveDebugFlowPhaseAlias(_ rawValue: String?) -> DebugFlowPhase? {
    guard let rawValue else { return nil }
    let normalized = rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if let exact = DebugFlowPhase(rawValue: normalized) {
        return exact
    }
    switch normalized {
    case "analyze", "analyzing", "analysis", "describe":
        return .describing
    case "reproduce", "reproducing":
        return .reproducing
    case "fix", "fixing":
        return .fixing
    case "instrument", "instrumenting":
        return .instrumenting
    case "verify", "verifying":
        return .verifying
    case "resolve", "resolved":
        return .resolved
    default:
        return nil
    }
}
