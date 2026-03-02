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

func isPlanExecutionProviderIdAllowed(_ providerId: String) -> Bool {
    ProviderSupport.isUserSelectableRealProvider(id: providerId)
}

func isPlanBuildExecutionCapableProvider(_ providerId: String, registry: ProviderRegistry) -> Bool {
    ProviderSupport.isPlanBuildExecutionCapableProvider(id: providerId, registry: registry)
}

func shouldHandlePlanKeyboardShortcut(isInputFocused: Bool) -> Bool {
    isInputFocused
}

func canStartPlanBuild(isLoading: Bool, phase: PlanFlowPhase) -> Bool {
    !isLoading && phase != .building
}

func shouldAllowStartingPlanBuild(
    isLoadingCurrentConversation: Bool,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    hasActiveBuildTask: Bool
) -> Bool {
    guard canStartPlanBuild(isLoading: isLoadingCurrentConversation, phase: phase) else {
        return false
    }
    if activeBuildPlanConversationId != nil && hasActiveBuildTask {
        return false
    }
    return true
}

func shouldClearPlanCanonicalTodosOnNewTurn(
    phase: PlanFlowPhase,
    hasActivePlanBuildTask: Bool
) -> Bool {
    if hasActivePlanBuildTask { return false }
    return phase != .building
}

func isPlanBuildContext(
    conversationId: UUID?,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> Bool {
    if phase == .building { return true }
    guard let conversationId else { return false }
    return conversationId == activeBuildPlanConversationId
        || conversationId == activeBuildAgentConversationId
}

func shouldResetPlanFlowAfterPreflightFailure(
    isPlanModeRequested: Bool,
    phase: PlanFlowPhase
) -> Bool {
    guard isPlanModeRequested else { return false }
    switch phase {
    case .analyzing, .questioning, .generating:
        return true
    case .idle, .proposalReady, .readyToBuild, .building:
        return false
    }
}

func shouldMutatePlanState(
    targetConversationId: UUID,
    currentConversationId: UUID?
) -> Bool {
    targetConversationId == currentConversationId
}

func shouldAllowPlanToggleDeactivation(phase: PlanFlowPhase) -> Bool {
    switch phase {
    case .analyzing, .questioning, .generating, .building:
        return false
    case .idle, .proposalReady, .readyToBuild:
        return true
    }
}

func shouldDisablePlanToggleWhenPanelCloses(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode
) -> Bool {
    guard coderMode != .plan else { return false }
    guard planningState == .idle else { return false }
    return shouldAllowPlanToggleDeactivation(phase: phase)
}

func shouldTreatConversationAsPlanContext(
    coderMode: CoderMode,
    hasInlinePlanSession: Bool,
    hasActivePlanFlowPhase: Bool,
    streamConversationId: UUID?,
    currentConversationId: UUID?,
    hasPlanBoardForStreamConversation: Bool,
    hasPlanBoardForCurrentConversation: Bool,
    showPlanPanel: Bool,
    activeBuildPlanConversationId: UUID?
) -> Bool {
    let isCurrentConversationStream: Bool = {
        guard let streamConversationId else { return true }
        guard let currentConversationId else { return false }
        return streamConversationId == currentConversationId
    }()

    if isCurrentConversationStream {
        if coderMode == .plan { return true }
        if hasInlinePlanSession { return true }
        if hasActivePlanFlowPhase { return true }
    }

    if let streamConversationId {
        // A persisted plan board alone must not force plan routing for normal
        // agent chat turns. Route only when an active plan session/build
        // is in progress.
        _ = hasPlanBoardForStreamConversation
        if streamConversationId == activeBuildPlanConversationId { return true }
        return false
    }

    if currentConversationId != nil {
        _ = hasPlanBoardForCurrentConversation
        if currentConversationId == activeBuildPlanConversationId { return true }
    }

    return false
}

func shouldRoutePlanStreamToPlanPanel(
    shouldRoutePlanStreamingToPanel: Bool,
    streamConversationId: UUID?,
    hasActivePlanContext: Bool,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> Bool {
    guard let streamConversationId else { return false }
    if hasActivePlanContext { return true }
    if phase == .building {
        if streamConversationId == activeBuildPlanConversationId { return true }
        if streamConversationId == activeBuildAgentConversationId { return true }
    }
    _ = shouldRoutePlanStreamingToPanel
    return false
}

func shouldHidePlanMarkdownInChat(
    shouldRoutePlanStreamToPanel: Bool,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool,
    fullLooksLikePlanPayload: Bool,
    shouldHidePlanMarkdownForBuild: Bool,
    hasActivePlanContext: Bool
) -> Bool {
    guard shouldRoutePlanStreamToPanel else { return false }
    return coderMode == .plan
        || shouldRunPlanInline
        || fullLooksLikePlanPayload
        || shouldHidePlanMarkdownForBuild
        || hasActivePlanContext
}

func resolvePlanStepTargetConversationId(
    eventConversationId: UUID?,
    activeBuildPlanConversationId: UUID?,
    activeTaskConversationId: UUID?
) -> UUID? {
    eventConversationId ?? activeBuildPlanConversationId ?? activeTaskConversationId
}

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
    If new ambiguities appear, you may ask follow-up questions again using ## Questions.
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
    true
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

struct ComposerFrozenTimerState: Equatable {
    let text: String
    let dismissible: Bool
    let autoHideDelay: TimeInterval?
}

func formatComposerElapsed(_ seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    let minutes = safeSeconds / 60
    let remainder = safeSeconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}

func buildComposerFrozenTimerState(
    elapsedSeconds: Int,
    endedByManualStop: Bool
) -> ComposerFrozenTimerState {
    ComposerFrozenTimerState(
        text: formatComposerElapsed(elapsedSeconds),
        dismissible: !endedByManualStop,
        autoHideDelay: endedByManualStop ? 2.0 : nil
    )
}

struct PlanCommandParseResult: Equatable {
    let displayedInput: String
    let llmPromptInput: String
    let forcePlanInline: Bool
}

func hasStrictPlanCommandPrefix(_ text: String) -> Bool {
    guard text.lowercased().hasPrefix("/plan") else { return false }
    guard text.count > 5 else { return true }
    let boundary = text.index(text.startIndex, offsetBy: 5)
    let next = text[boundary]
    return next.isWhitespace || next.isNewline
}

func shouldUseClarificationPrompt(
    coderMode: CoderMode,
    planningState: PlanningState,
    shouldRunPlanInline: Bool
) -> Bool {
    guard case .awaitingClarification = planningState else { return false }
    return coderMode == .plan || shouldRunPlanInline
}

func parsePlanCommandInput(_ rawInput: String) -> PlanCommandParseResult {
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard hasStrictPlanCommandPrefix(text) else {
        return PlanCommandParseResult(
            displayedInput: text,
            llmPromptInput: text,
            forcePlanInline: false
        )
    }
    let remainder = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = remainder.isEmpty
        ? "Generate a structured plan with alternative options, pros/cons, and complexity."
        : remainder
    return PlanCommandParseResult(
        displayedInput: prompt,
        llmPromptInput: prompt,
        forcePlanInline: true
    )
}

func isShiftTabShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?, keyCode: UInt16)
    -> Bool
{
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    let isBacktabChar = charsIgnoringModifiers == "\u{19}"
    let isTabKeycode = keyCode == 48
    return (isBacktabChar || isTabKeycode)
        && normalized.contains(.shift)
        && !normalized.contains(.command)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
}

func isCmdShiftPShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?) -> Bool {
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    return normalized.contains(.command)
        && normalized.contains(.shift)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
        && charsIgnoringModifiers?.lowercased() == "p"
}

struct ShiftTabPlanShortcutTransition: Equatable {
    let nextInputText: String
    let shouldFocusInput: Bool
    let shouldHighlightPlanToggle: Bool
    let shouldEnablePlanToggle: Bool
}

func evaluateShiftTabPlanShortcut(currentInputText: String) -> ShiftTabPlanShortcutTransition {
    let trimmed = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return ShiftTabPlanShortcutTransition(
            nextInputText: "/plan ",
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true
        )
    }
    if trimmed.lowercased().hasPrefix("/plan") {
        return ShiftTabPlanShortcutTransition(
            nextInputText: currentInputText,
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true
        )
    }
    return ShiftTabPlanShortcutTransition(
        nextInputText: "/plan " + trimmed,
        shouldFocusInput: true,
        shouldHighlightPlanToggle: false,
        shouldEnablePlanToggle: true
    )
}

func shouldOpenPlanPanelAfterShiftTab(
    shouldEnablePlanToggle: Bool,
    currentShowPlanPanel: Bool
) -> Bool {
    shouldEnablePlanToggle && !currentShowPlanPanel
}

struct CmdShiftPPlanShortcutTransition: Equatable {
    let nextPlanToggleEnabled: Bool
    let nextShowPlanPanel: Bool
}

func evaluateCmdShiftPPlanShortcut(
    currentPlanToggleEnabled: Bool,
    currentShowPlanPanel: Bool
) -> CmdShiftPPlanShortcutTransition {
    // 1) off/off -> enable inline Plan (chat badge)
    if !currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: false
        )
    }

    // 2) on/off -> open plan panel
    if currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: true
        )
    }

    // 3) any state with panel open -> turn off everything
    return CmdShiftPPlanShortcutTransition(
        nextPlanToggleEnabled: false,
        nextShowPlanPanel: false
    )
}

enum PlanPanelAutoOpenTrigger: Equatable {
    case flowStarted
    case planStepUpdate
    case awaitingClarification
    case awaitingChoice
}

func shouldAutoOpenPlanPanel(trigger: PlanPanelAutoOpenTrigger) -> Bool {
    switch trigger {
    case .flowStarted:
        return true
    case .awaitingClarification:
        return true
    case .awaitingChoice:
        return true
    case .planStepUpdate:
        return false
    }
}

func resolveShouldRunPlanInline(
    forcePlanInline: Bool,
    coderMode: CoderMode,
    planToggleEnabled: Bool
) -> Bool {
    forcePlanInline || (coderMode == .agent && planToggleEnabled)
}

struct InlinePlanSummary: Equatable {
    let title: String
    let body: String
}

struct ToolTraceTurnContext: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let providerId: String
}

struct PolicyAckState: Equatable {
    let expectedHash: String
    var acknowledgedHash: String?
    var violationEmitted: Bool = false

    var isSatisfied: Bool {
        acknowledgedHash == expectedHash
    }
}
