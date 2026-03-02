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
    reviewTodoTitle: String = "Code Review & Test"
) -> [UUID] {
    let normalizedReviewTitle = reviewTodoTitle
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    var ids = Set(todos.filter { $0.status == .inProgress }.map(\.id))
    if let pendingReview = todos.first(where: {
        $0.status == .pending
            && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedReviewTitle
    }) {
        ids.insert(pendingReview.id)
    }
    return Array(ids)
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

private func hasStrictPlanCommandPrefix(_ text: String) -> Bool {
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
    let nextPrimedUntil: Date?
}

func evaluateShiftTabPlanShortcut(
    now: Date,
    primedUntil: Date?,
    currentInputText: String
) -> ShiftTabPlanShortcutTransition {
    _ = now
    _ = primedUntil
    let trimmed = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return ShiftTabPlanShortcutTransition(
            nextInputText: "/plan ",
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true,
            nextPrimedUntil: nil
        )
    }
    if trimmed.lowercased().hasPrefix("/plan") {
        return ShiftTabPlanShortcutTransition(
            nextInputText: currentInputText,
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true,
            nextPrimedUntil: nil
        )
    }
    return ShiftTabPlanShortcutTransition(
        nextInputText: "/plan " + trimmed,
        shouldFocusInput: true,
        shouldHighlightPlanToggle: false,
        shouldEnablePlanToggle: true,
        nextPrimedUntil: nil
    )
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

private struct InlinePlanSummary: Equatable {
    let title: String
    let body: String
}

private struct ToolTraceTurnContext: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let providerId: String
}

private struct PolicyAckState: Equatable {
    let expectedHash: String
    var acknowledgedHash: String?
    var violationEmitted: Bool = false

    var isSatisfied: Bool {
        acknowledgedHash == expectedHash
    }
}

struct ChatPanelView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @EnvironmentObject var browserTabManager: BrowserTabManager
    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext

    private var conversationId: UUID? { selectedConversationId }

    /// Loading state only for the currently displayed thread (avoids showing loading for other threads).
    private var isLoadingForCurrentConversation: Bool {
        chatStore.isTaskActive(for: conversationId)
            || (planFlowPhase == .building && activeBuildPlanConversationId == conversationId)
    }

    @Binding var coderMode: CoderMode
    @State private var inputText = ""
    @State private var isInputFocused: Bool = false
    @State private var didAutoFocusComposerOnLaunch: Bool = false
    @State private var composerAutoFocusTask: Task<Void, Never>?
    @State private var draftSaveTask: Task<Void, Never>?
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_session_full_access") private var codexSessionFullAccess = false
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") private var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    private var codexPreferResponsesWireAPI = false
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "auto"
    @AppStorage("swarm_provider_auto_migrated_v1") private var swarmProviderAutoMigrated = false
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles =
        "explorer,coder,debugger,reviewer,testWriter"
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "auto"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "auto"
    @AppStorage("code_review_quick_commands_custom_json")
    private var codeReviewQuickCommandsCustomJSON = ""
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"
    @State private var codexModels: [CodexModel] = []
    @State private var geminiModels: [GeminiModel] = []
    @State private var showSwarmHelp = false
    @AppStorage("task_panel_enabled") private var taskPanelEnabled = true
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools = "Read,Edit,Bash,Write,Search"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled") private var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") private var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled") private var mcpEditEnforcementEnabled = true
    @AppStorage("web_search_provider") private var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") private var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") private var tavilyApiKey = ""
    @AppStorage("serper_api_key") private var serperApiKey = ""
    @AppStorage("multi_cli_account_enabled") private var multiCLIAccountEnabled = false
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @AppStorage("context_scope_mode") private var contextScopeModeRaw = "auto"
    @AppStorage("plan_panel_width") private var planPanelWidthStorage: Double = 320
    @AppStorage("debug_panel_width") private var debugPanelWidthStorage: Double = 340
    @AppStorage("swarm_panel_width") private var swarmPanelWidthStorage: Double = 360
    @AppStorage("code_review_panel_width") private var codeReviewPanelWidthStorage: Double = 380
    @AppStorage("auto_resize_side_panels") private var autoResizeSidePanels = false
    @State private var planToggleEnabled = false
    @State private var debugToggleEnabled = false
    @Binding var showPlanPanel: Bool
    @Binding var showDebugPanel: Bool
    @Binding var showSwarmPanel: Bool
    @Binding var showCodeReviewPanel: Bool
    @Binding var showBrowserPanel: Bool
    @State private var selectedSwarmId: String?
    @State private var planPanelPresentationSource: PlanPanelPresentationSource = .manualDeepLink
    @ObservedObject var debugStore: DebugStore
    @State private var planningState: PlanningState = .idle
    @State private var planFlowPhase: PlanFlowPhase = .idle
    @State private var planAnalysisContext: String = ""
    @State private var planUserRequest: String = ""
    @State private var planClarificationAnswers: String = ""
    @State private var planClarificationCycles: Int = 0
    @State private var planStreamingContent: String = ""
    @State private var planShouldRunInline: Bool = false
    @State private var activeBuildPlanConversationId: UUID?
    @State private var activeBuildAgentConversationId: UUID?
    @State private var suppressedEmptyBuildAssistantMessageIds: Set<UUID> = []
    @State private var isProviderReady = false
    @State private var attachedComposerAttachments: [ComposerAttachment] = []
    @State private var isSelectingImage = false
    @State private var isComposerDropTargeted = false
    @State private var isConvertingHeic = false
    @State private var pasteMonitor: Any?
    @State private var isSummarizing = false
    @State private var isRewinding = false
    @State private var isPlanSummaryCollapsed = false
    @State private var isPlanTabHovered = false
    @State private var planShortcutPrimedUntil: Date?
    @State private var isPlanShortcutCycling = false
    @State private var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
    @State private var hasJustCompletedTask = false
    @State private var showRateLimitAlert = false
    @State private var rateLimitAlertText = ""
    @State private var didCopyAllChat = false
    @State private var isFollowingLive = true
    @State private var newEventsWhileDetached = 0
    @State private var chatHeaderWidth: CGFloat = 800
    @StateObject private var voiceInputController = VoiceInputController()
    @State private var composerFrozenTimerState: ComposerFrozenTimerState?
    @State private var composerTimerAutoHideTask: Task<Void, Never>?
    @State private var composerTaskStartDate: Date?
    @State private var lastTaskEndedByManualStop = false

    // MARK: - Prompt Optimizer State
    @State private var isOptimizingPrompt = false
    @State private var showPromptOptimizerPopup = false
    @State private var optimizedPromptResult = ""
    @State private var promptOptimizerTask: Task<Void, Never>?

    @State private var isAnyAgentProviderReady = false
    @State private var checkProviderAuthGeneration = 0
    @State private var userModeOverrideUntilConversationChange = false
    @State private var suppressModeSyncForNextProviderChange = false
    @State private var ignoreNextConversationChangeReset = false
    @State private var skipNextLoadingCompletedHandling = false
    @StateObject private var flowCoordinator = ConversationFlowCoordinator()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var pendingTaskActivities: [TaskActivity] = []
    @State private var pendingInstantGreps: [InstantGrepResult] = []
    @State private var taskFlushTask: Task<Void, Never>?
    @State private var autoScrollWorkItem: DispatchWorkItem?
    @State private var lastAutoScrollTarget: AnyHashable?
    @State private var lastAutoScrollAt: Date = .distantPast
    @State private var fallbackTurnStartWorkItem: DispatchWorkItem?
    @State private var streamContentVersion: Int = 0
    @State private var streamingReasoningText: String?
    @State private var streamingReasoningConversationId: UUID?
    @State private var streamingReasoningBlocks: [ReasoningBlock] = []
    @State private var streamingSegments: [MessageSegment] = []
    @State private var streamingSegmentTurnIndex: Int = 0
    /// Pending streaming content waiting to be flushed to ChatStore.
    @State private var pendingStreamContent: String?
    @State private var pendingStreamConversationId: UUID?
    @State private var streamThrottleTask: Task<Void, Never>?
    /// Pending plan-streaming content while the flow is rendering in the panel.
    @State private var pendingPlanStreamingContent: String?
    @State private var pendingPlanStreamConversationId: UUID?
    @State private var planStreamThrottleTask: Task<Void, Never>?
    @State private var toolRuntimeSyncTask: Task<Void, Never>?
    @State private var activeRunTaskByConversation: [UUID: Task<Void, Never>] = [:]
    @State private var activeRunTokenByConversation: [UUID: UUID] = [:]
    @State private var activeToolTraceTurnsByConversation: [UUID: ToolTraceTurnContext] = [:]
    @State private var toolTraceNextSequenceByMessage: [UUID: Int] = [:]
    @State private var toolTraceOperationalSeenByMessage: [UUID: Bool] = [:]
    @State private var toolTraceOperationalCountByMessage: [UUID: Int] = [:]
    @State private var policyAckStateByMessage: [UUID: PolicyAckState] = [:]
    /// Assistant message ids that already triggered a policy-ack violation.
    @State private var policyAckFailedMessages: Set<UUID> = []
    /// Events queued while waiting for policy_ack, keyed by assistant message id.
    @State private var policyAckBlockedQueue: [UUID: [(type: String, payload: [String: String], providerId: String, conversationId: UUID?)]] = [:]
    /// Per-conversation debug state snapshots (prevents cross-thread contamination).
    @State private var debugStateByConversation: [UUID: DebugStore.SessionSnapshot] = [:]
    /// Debug events received while another conversation is selected.
    @State private var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]
    @State private var autoTodoIdByMessage: [UUID: UUID] = [:]
    @State private var autoTodoCompletedOperationsByMessage: [UUID: Int] = [:]
    @State private var didReceiveExplicitTodoByMessage: Set<UUID> = []
    /// Minimum interval between streaming content updates.
    /// Adaptive: starts at ~60fps (0.016s) for fast LLMs, scales to ~30fps if needed.
    private let streamThrottleInterval: TimeInterval = 0.020
    /// Minimum interval for plan-streaming updates routed to the Plan Panel.
    private let planStreamThrottleInterval: TimeInterval = 0.066
    /// Coalescing flush interval for task activity feed.
    private let taskActivityFlushInterval: TimeInterval = 0.1
    /// Backlog threshold used only for lightweight stream diagnostics.
    private let taskBacklogDiagnosticThreshold = 40
    private let checkpointGitStore = ConversationCheckpointGitStore()
    private let cliAccountsStore = CLIAccountsStore.shared
    private let cliAccountRouter = CLIAccountRouter.shared

    private static let attachmentPastedNotification = Notification.Name("CoderIDE.AttachmentPasted")
    static let planBuildShortcutNotification = Notification.Name("CoderIDE.PlanBuildShortcutPressed")
    static let debugPanelToggleNotification = Notification.Name("CoderIDE.DebugPanelToggle")
    private static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
    private static let markdownExportContentType = UTType(filenameExtension: "md") ?? .plainText
    private let topInteractiveInset: CGFloat = 22
    private let chatColumnMaxWidth: CGFloat = 960

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }
    private var showPlanRequestIndicator: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return planToggleEnabled || hasStrictPlanCommandPrefix(trimmed)
    }
    private var composerRuntimeStartDate: Date? {
        guard isLoadingForCurrentConversation else { return nil }
        return chatStore.taskStartDate(for: conversationId) ?? composerTaskStartDate
    }
    private var composerFrozenTimerText: String? { composerFrozenTimerState?.text }
    private var composerFrozenTimerDismissible: Bool { composerFrozenTimerState?.dismissible == true }
    private var shouldShowTaskPanelTodoSection: Bool {
        let planFlowActive =
            coderMode == .plan
            || planToggleEnabled
            || planFlowPhase == .analyzing
            || planFlowPhase == .questioning
            || planFlowPhase == .generating
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
        return !planFlowActive
    }
    private var isPlanPreChoiceState: Bool {
        if planningState != .idle {
            return true
        }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .proposalReady:
            return true
        case .idle, .readyToBuild, .building:
            return false
        }
    }
    private var hasInlinePlanSession: Bool {
        coderMode == .plan || (coderMode == .agent && planToggleEnabled)
    }
    private var hasActivePlanContext: Bool {
        hasActivePlanContext(for: conversationId)
    }
    private var planInPanelPlaceholder: String {
        "Plan available in the Plan Panel."
    }
    private var shouldShowPlanTodosInChat: Bool {
        return true
    }
    private var shouldRoutePlanStreamingToPanel: Bool {
        return hasActivePlanContext
    }
    private var shouldShowPlanBoardInChat: Bool {
        false
    }
    private var shouldShowInlinePlanSummaryInChat: Bool {
        false
    }
    private var shouldShowPlanAttachmentsInChat: Bool {
        false
    }

    private var hasActivePlanFlowPhase: Bool {
        planFlowPhase == .analyzing
        || planFlowPhase == .questioning
        || planFlowPhase == .generating
        || planFlowPhase == .proposalReady
        || planFlowPhase == .readyToBuild
        || planFlowPhase == .building
    }

    private func hasActivePlanContext(for streamConversationId: UUID?) -> Bool {
        let hasPlanBoardForStreamConversation: Bool = {
            guard let streamConversationId else { return false }
            return chatStore.planBoard(for: streamConversationId) != nil
        }()
        let hasPlanBoardForCurrentConversation: Bool = {
            guard let currentConversationId = conversationId else { return false }
            return chatStore.planBoard(for: currentConversationId) != nil
        }()
        return shouldTreatConversationAsPlanContext(
            coderMode: coderMode,
            hasInlinePlanSession: hasInlinePlanSession,
            hasActivePlanFlowPhase: hasActivePlanFlowPhase,
            streamConversationId: streamConversationId,
            currentConversationId: conversationId,
            hasPlanBoardForStreamConversation: hasPlanBoardForStreamConversation,
            hasPlanBoardForCurrentConversation: hasPlanBoardForCurrentConversation,
            showPlanPanel: showPlanPanel,
            activeBuildPlanConversationId: activeBuildPlanConversationId
        )
    }

    private func looksLikePlanPayload(_ rawText: String) -> Bool {
        let cleaned = ChatStore
            .stripCoderideMarkers(rawText, aggressive: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let lower = cleaned.lowercased()
        let hasPlanSignalToken =
            lower.contains("## plan")
            || lower.contains("## questions")
            || lower.contains("## option")
            || lower.contains("## todo")
            || lower.contains("```mermaid")
            || lower.contains("- [")
        guard hasPlanSignalToken else { return false }

        let hasPlanLikeHeader = cleaned.range(
            of: #"(?im)^\s*##\s*(?:plan|questions?|clarification|option(?:s)?|todo|to-do)\b"#,
            options: .regularExpression
        ) != nil
        if hasPlanLikeHeader { return true }

        if PlanOptionsParser.hasRequiredTodoHeader(cleaned) { return true }

        let hasChecklist = cleaned.range(
            of: #"(?im)^\s*[-*]\s*\[[ xX]?\]\s+"#,
            options: .regularExpression
        ) != nil
        let hasMermaid = cleaned.range(
            of: #"(?im)^\s*```mermaid\b"#,
            options: .regularExpression
        ) != nil
        return hasChecklist || hasMermaid
    }

    private func shouldSuppressPlanArtifactsInChat(
        message: ChatMessage,
        conversationId: UUID?
    ) -> Bool {
        guard message.role == .assistant else { return false }
        guard hasActivePlanContext(for: conversationId) else { return false }
        guard looksLikePlanPayload(message.content) else {
            let hasMermaidBlock = message.content.range(
                of: #"(?im)^\s*```mermaid\b"#,
                options: .regularExpression
            ) != nil
            return hasMermaidBlock
        }
        return true
    }

    private func chatDisplayMessage(
        from message: ChatMessage,
        conversationId _: UUID?
    ) -> ChatMessage {
        var displayMessage = message
        displayMessage.content = planInPanelPlaceholder
        return displayMessage
    }
    private var showsSwarmViewOnly: Bool { shouldShowSwarmViewOnly(for: coderMode) }
    private var planPanelConversationId: UUID? { conversationId }
    private var shouldShowFinalChatActions: Bool {
        Self.shouldShowFinalChatActions(
            conversation: chatStore.conversation(for: conversationId),
            isLoadingForCurrentConversation: isLoadingForCurrentConversation
        ) && !showsSwarmViewOnly
    }

    var body: some View {
        applyNotificationAndImporterModifiers(
            to: applyRuntimeLifecycleModifiers(
                to: applyProviderSelectionModifiers(to: rootLayout)
            )
        )
    }

    @ViewBuilder
    private var rootLayout: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep out of macOS titlebar hit-test zone while still using full-height content.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
                chatHeader

                ConnectionStatusBanner(monitor: networkMonitor)

                if coderMode == .agent
                    && (!swarmProgressStore.steps.isEmpty
                        || !taskActivityStore.swarmCards.isEmpty)
                {
                    SwarmProgressView(
                        store: swarmProgressStore,
                        activities: taskActivityStore.activities,
                        isTaskRunning: isLoadingForCurrentConversation,
                        onSelectSwarm: { swarmId in
                            showSwarmPanel = true
                            selectedSwarmId = swarmId
                        }
                    )
                }

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    messagesArea
                }

                if shouldShowFinalChatActions {
                    finalChatActionsBar
                }

                // Keep the legacy task bar only when the composer is not visible (e.g. Swarm).
                if !shouldShowComposer(for: coderMode) && (isLoadingForCurrentConversation || isSummarizing) {
                    TaskControlBar(
                        chatStore: chatStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        conversationId: conversationId,
                        coderMode: coderMode,
                        debugPhase: debugStore.phase,
                        isSummarizing: isSummarizing,
                        activeModeColor: activeModeColor,
                        onInterrupt: { interruptTask() }
                    )
                }

                if shouldShowComposer(for: coderMode) {
                    composerArea
                }
                if shouldShowUsageFooter(for: coderMode) {
                    usageFooterArea
                }
            }
            if showPlanPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(planPanelWidthStorage) }, set: { planPanelWidthStorage = Double($0) }),
                    minWidth: 220, maxWidth: 500, leadingEdge: true
                )
                planPanelSidebar
            }
            if showDebugPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(debugPanelWidthStorage) }, set: { debugPanelWidthStorage = Double($0) }),
                    minWidth: 240, maxWidth: 500, leadingEdge: true
                )
                debugPanelSidebar
            }
            if showSwarmPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(swarmPanelWidthStorage) }, set: { swarmPanelWidthStorage = Double($0) }),
                    minWidth: 260, maxWidth: 540, leadingEdge: true
                )
                swarmPanelSidebar
            }
            if showCodeReviewPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(codeReviewPanelWidthStorage) }, set: { codeReviewPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 560, leadingEdge: true
                )
                codeReviewPanelSidebar
            }
        }
        .animation(.none, value: showPlanPanel)
        .animation(.none, value: showDebugPanel)
        .animation(.none, value: showSwarmPanel)
        .animation(.none, value: showCodeReviewPanel)
    }

    private func applyProviderSelectionModifiers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: providerRegistry.selectedProviderId) { _, newId in
            if shouldSyncModeOnProviderChange(suppressForUserPicker: suppressModeSyncForNextProviderChange) {
                syncCoderModeToProvider(newId)
            } else {
                suppressModeSyncForNextProviderChange = false
            }
            checkProviderAuth()
        }
        .onChange(of: selectedConversationId) { oldId, newId in
            draftSaveTask?.cancel()
            draftSaveTask = nil
            persistDebugState(for: oldId)
            // Save draft text for the previous conversation.
            if let oldId {
                let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    chatStore.draftTexts.removeValue(forKey: oldId)
                } else {
                    chatStore.draftTexts[oldId] = inputText
                }
            }
            // Restore draft text for the new conversation (or clear).
            inputText = chatStore.draftTexts[newId ?? UUID()] ?? ""

            if ignoreNextConversationChangeReset {
                ignoreNextConversationChangeReset = false
            } else {
                userModeOverrideUntilConversationChange = false
            }
            planShortcutPrimedUntil = nil
            // Allow the previous thread to keep running in the background —
            // don't nil out activeBuildPlanConversationId here so the
            // build completion handler can still finalize successfully.
            planHistoryStore.setSelectedEntry(id: nil)
            // Close side panels that are scoped to the previous conversation.
            showSwarmPanel = false
            selectedSwarmId = nil
            restoreDebugState(for: newId)
            applyPendingDebugEvents(for: newId)
            if debugStore.phase == .idle {
                showDebugPanel = false
                debugToggleEnabled = false
                if coderMode == .debug {
                    selectMode(.agent)
                }
            } else {
                debugToggleEnabled = true
                showDebugPanel = debugStore.phase.isActive
            }
            // Clear per-turn activity data so the swarm panel doesn't show
            // activities from the previous conversation when reopened.
            taskActivityStore.clearSwarmCards()
            swarmProgressStore.clear()
            syncProviderFromConversation()
            restorePlanStateIfNeeded(for: newId)
            requestInitialComposerFocusIfNeeded()
        }
        .onAppear {
            migrateSwarmProviderDefaultsIfNeeded()
            syncProviderFromConversation()
            scheduleToolRuntimePolicySync(immediate: true)
            codexModels = CodexModelsCache.loadModels()
            geminiModels = GeminiModelsCache.loadModels()
            syncSwarmProvider()
            syncCodeReviewRuntimeConfig()
            syncPlanProvider()
            checkProviderAuth()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            restorePlanStateIfNeeded(for: selectedConversationId)
            wireTodoPlanBidirectionalSync()
            requestInitialComposerFocusIfNeeded()
        }
    }

    /// Wire bidirectional sync: when a canonical todo status changes manually,
    /// propagate the change to the corresponding PlanStep in the plan board.
    /// Idempotent — safe to call multiple times (e.g. from onAppear).
    private func wireTodoPlanBidirectionalSync() {
        // Guard: don't re-register if callback already set (onAppear fires multiple times).
        guard todoStore.onCanonicalTodoStatusChange == nil else { return }
        todoStore.onCanonicalTodoStatusChange = { [weak chatStore] _, _ in
            guard let chatStore else { return }
            let planConvId = activeBuildPlanConversationId
                ?? chatStore.preferredPlanConversationIdForCanonicalSync()
            let canonicalTodos = todoStore.todos.filter(\.isPlanCanonical)
            if let activeId = planConvId, !canonicalTodos.isEmpty {
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: activeId)
            }
        }
    }

    private func adjustWindowForPanelToggle(isOpening: Bool, width: CGFloat) {
        guard autoResizeSidePanels else { return }
        let delta = isOpening ? (width + 12) : -(width + 12)
        DispatchQueue.main.async {
            WindowResizeHelper.adjustWidth(by: delta, animate: false)
        }
    }

    private func applyRuntimeLifecycleModifiers<Content: View>(to content: Content) -> some View {
        let lifecycleTracked = content
            .onChange(of: showSwarmPanel) { wasOpen, isShowing in
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(swarmPanelWidthStorage))
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(swarmPanelWidthStorage))
                }
            }
            .onChange(of: showDebugPanel) { wasOpen, isShowing in
                if debugToggleEnabled != isShowing {
                    debugToggleEnabled = isShowing
                }
                if isShowing && showPlanPanel {
                    showPlanPanel = false
                    planToggleEnabled = false
                }
                if isShowing && coderMode != .debug {
                    selectMode(.debug)
                } else if !isShowing && coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(debugPanelWidthStorage))
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(debugPanelWidthStorage))
                }
            }
            .onChange(of: debugToggleEnabled) { _, isEnabled in
                guard showDebugPanel != isEnabled else { return }
                showDebugPanel = isEnabled
            }
            // Auto-expand/shrink window when side panels open/close
            .onChange(of: showPlanPanel) { wasOpen, isOpen in
                if isOpen && showDebugPanel {
                    debugToggleEnabled = false
                    showDebugPanel = false
                }
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(planPanelWidthStorage))
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(planPanelWidthStorage))
                    if planPanelPresentationSource == .automaticFlow {
                        planPanelPresentationSource = .manualDeepLink
                    }
                }
                if isOpen {
                    planToggleEnabled = true
                } else if wasOpen,
                          !isPlanShortcutCycling,
                          shouldDisablePlanToggleWhenPanelCloses(
                            phase: planFlowPhase,
                            planningState: planningState,
                            coderMode: coderMode
                          )
                {
                    planToggleEnabled = false
                }
            }
            .onChange(of: planToggleEnabled) { _, isEnabled in
                // Keep planner panel visibility in sync with the composer inline-plan button.
                if isEnabled {
                    if !showPlanPanel && !isPlanShortcutCycling {
                        openPlanPanelForCurrentContext(source: .manualShortcut)
                    }
                } else if showPlanPanel && shouldAllowPlanToggleDeactivation(phase: planFlowPhase) {
                    showPlanPanel = false
                    planningState = .idle
                    planFlowPhase = .idle
                    clearPlanStreamingState()
                    planHistoryStore.setSelectedEntry(id: nil)
                }
            }
            .onChange(of: showCodeReviewPanel) { wasOpen, isOpen in
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(codeReviewPanelWidthStorage))
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(codeReviewPanelWidthStorage))
                }
            }
            .onChange(of: effectiveContext.primaryPath) { _, newPath in
                gitPanelStore.refresh(workingDirectory: newPath)
            }
            .onChange(of: taskActivityStore.swarmEventsAssignedCount) { oldCount, newCount in
                if oldCount == 0, newCount > 0, !showSwarmPanel, isLoadingForCurrentConversation {
                    showSwarmPanel = true
                }
            }
            .onChange(of: selectedConversationId) { _, _ in
                gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                composerFrozenTimerState = nil
                composerTaskStartDate = nil
                composerTimerAutoHideTask?.cancel()
                composerTimerAutoHideTask = nil
                lastTaskEndedByManualStop = false
            }
            .onChange(of: inputText) { _, newValue in
                guard let cid = conversationId else { return }
                draftSaveTask?.cancel()
                draftSaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
                    guard !Task.isCancelled else { return }
                    draftSaveTask = nil
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        chatStore.draftTexts.removeValue(forKey: cid)
                    } else {
                        chatStore.draftTexts[cid] = newValue
                    }
                }
            }
            .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                guard let cid = conversationId else { return }
                let wasActive = oldSet.contains(cid)
                let isActive = newSet.contains(cid)
                if !wasActive && isActive {
                    composerTaskStartDate = chatStore.taskStartDate(for: cid) ?? Date()
                    composerFrozenTimerState = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    lastTaskEndedByManualStop = false
                }
                if wasActive && !isActive {
                    if skipNextLoadingCompletedHandling {
                        skipNextLoadingCompletedHandling = false
                        return
                    }
                    hasJustCompletedTask = true
                    gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    let startDate = composerTaskStartDate ?? Date()
                    let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))
                    let frozen = buildComposerFrozenTimerState(
                        elapsedSeconds: elapsed,
                        endedByManualStop: lastTaskEndedByManualStop
                    )
                    composerFrozenTimerState = frozen
                    composerTaskStartDate = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    if let delay = frozen.autoHideDelay {
                        composerTimerAutoHideTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            if !self.isLoadingForCurrentConversation {
                                composerFrozenTimerState = nil
                            }
                        }
                    }
                    lastTaskEndedByManualStop = false
                }
            }

        let swarmTracked = lifecycleTracked
            .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
            .onChange(of: claudeAllowedTools) { _, _ in
                syncClaudeProvider()
            }
            .onChange(of: unifiedToolRuntimeEnabled) { _, _ in
                syncClaudeProvider()
                syncGeminiProvider()
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: mcpEditEnforcementEnabled) { _, _ in
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: globalYolo) { _, _ in
                syncCodexProvider()
                syncCodeReviewRuntimeConfig()
                syncPlanProvider()
            }

        let workspaceTracked = swarmTracked
            .onChange(of: workspaceStore.activeWorkspaceId) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: workspaceStore.workspaces.map(\.id)) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: projectContextStore.activeContextId) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: effectiveContext.folderPaths) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }

        return workspaceTracked
            .onChange(of: codeReviewPartitions) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewMaxRounds) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisBackend) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewExecutionBackend) { _, _ in syncCodeReviewRuntimeConfig() }
    }

    private func applyNotificationAndImporterModifiers<Content: View>(to content: Content) -> some View {
        content
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
        .fileImporter(
            isPresented: $isSelectingImage,
            allowedContentTypes: [.item], allowsMultipleSelection: true
        ) { result in
            handleAttachmentSelection(result: result)
        }
        .onAppear {
            installPasteMonitor()
        }
        .onDisappear {
            composerAutoFocusTask?.cancel()
            composerAutoFocusTask = nil
            toolRuntimeSyncTask?.cancel()
            toolRuntimeSyncTask = nil
            taskFlushTask?.cancel()
            taskFlushTask = nil
            streamThrottleTask?.cancel()
            streamThrottleTask = nil
            planStreamThrottleTask?.cancel()
            planStreamThrottleTask = nil
            autoScrollWorkItem?.cancel()
            composerTimerAutoHideTask?.cancel()
            composerTimerAutoHideTask = nil
            voiceInputController.cancel()
            flushPendingTaskActivities()
            removePasteMonitor()
            for (_, task) in activeRunTaskByConversation {
                task.cancel()
            }
            activeRunTaskByConversation.removeAll()
            activeRunTokenByConversation.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.attachmentPastedNotification)) {
            notification in
            if let attachments = notification.userInfo?["attachments"] as? [ComposerAttachment] {
                appendComposerAttachments(attachments)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.threadSearchAskAINotification)) {
            notification in
            guard let prompt = notification.userInfo?["prompt"] as? String else { return }
            if selectedConversationId == nil {
                selectedConversationId = chatStore.createConversation(
                    contextId: nil, contextFolderPath: nil, mode: coderMode)
            }
            inputText = prompt
            sendMessage()
        }
    }

    @MainActor
    private func requestInitialComposerFocusIfNeeded() {
        guard !didAutoFocusComposerOnLaunch else { return }
        guard selectedConversationId != nil else { return }
        didAutoFocusComposerOnLaunch = true
        composerAutoFocusTask?.cancel()
        composerAutoFocusTask = Task { @MainActor in
            // Delay slightly to ensure the window/composer NSView is mounted.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
    }

    @ViewBuilder
    private var planPanelSidebar: some View {
        PlanPanelView(
            todoStore: todoStore,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            conversationId: planPanelConversationId,
            isCurrentConversationLoading: isLoadingForCurrentConversation,
            planningState: planningState,
            planFlowPhase: planFlowPhase,
            planStreamingContent: planStreamingContent,
            showHistorySection: shouldShowPlanPanelHistory(source: planPanelPresentationSource),
            workspaceSource: planPanelPresentationSource,
            onClose: {
                showPlanPanel = false
            },
            onSelectOption: { option, providerId in
                selectPlanChoice(
                    option.fullText,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId
                )
            },
            onCustomResponse: { response in
                handleCustomPlanResponseSelection(
                    response,
                    fromPlanConversationId: planPanelConversationId
                )
            },
            onSubmitClarificationAnswers: { answers in
                submitPlanClarificationAnswers(answers)
            },
            onBuild: { choice, providerId, allowIdleRebuild in
                executeWithPlanChoice(
                    choice,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId,
                    allowIdleRebuild: allowIdleRebuild
                )
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
            },
            onHistoryEntrySelectedForBuild: {
                if planFlowPhase == .idle, planningState == .idle {
                    planFlowPhase = .readyToBuild
                }
            }
        )
        .frame(width: CGFloat(planPanelWidthStorage))
    }

    @ViewBuilder
    private var debugPanelSidebar: some View {
        DebugPanelView(
            debugStore: debugStore,
            taskActivities: scopedTaskActivities(for: conversationId),
            todoStore: todoStore,
            onClose: {
                debugToggleEnabled = false
                showDebugPanel = false
                if coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
            },
            onSubmitQuestion: { question in
                let debugPrompt = "[DEBUG] \(question)"
                inputText = debugPrompt
                sendMessage()
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
                debugStore.resetSession()
            },
            onProceed: {
                debugStore.confirmReproduced()
                // Tell the agent to proceed with investigation
                inputText = "[DEBUG] Bug reproduced. Proceed with investigation."
                sendMessage()
            },
            onFixed: {
                let filesToClean = debugStore.beginMarkFixed(summary: debugStore.resolutionSummary)
                if filesToClean.isEmpty {
                    inputText = "[DEBUG] Run debug_clean now and confirm cleanup succeeded, then resolve the session."
                } else {
                    let fileList = filesToClean.joined(separator: ", ")
                    inputText = "[DEBUG] Run debug_clean for these files: \(fileList). After success, resolve the session."
                }
                sendMessage()
            }
        )
        .frame(width: CGFloat(debugPanelWidthStorage))
    }

    @ViewBuilder
    private var swarmPanelSidebar: some View {
        SwarmPanelView(
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            chatStore: chatStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            selectedSwarmId: $selectedSwarmId,
            swarmOrchestrator: $swarmOrchestrator,
            swarmWorkerBackend: $swarmWorkerBackend,
            onClose: {
                showSwarmPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onSyncSwarmProvider: syncSwarmProvider
        )
        .frame(width: CGFloat(swarmPanelWidthStorage))
    }

    private var codeReviewPanelSidebar: some View {
        CodeReviewPanelView(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            coderMode: coderMode,
            codeReviewPartitions: $codeReviewPartitions,
            codeReviewAnalysisOnly: $codeReviewAnalysisOnly,
            codeReviewMaxRounds: $codeReviewMaxRounds,
            codeReviewAnalysisBackend: $codeReviewAnalysisBackend,
            codeReviewExecutionBackend: $codeReviewExecutionBackend,
            onClose: {
                showCodeReviewPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onRunSlashCommand: { command in
                inputText = command
                isInputFocused = true
                sendMessage()
            },
            onSelectMode: { mode in
                selectMode(mode)
            }
        )
        .frame(width: CGFloat(codeReviewPanelWidthStorage))
    }

    @ViewBuilder
    private var swarmDashboardArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SwarmProgressView(
                    store: swarmProgressStore,
                    activities: taskActivityStore.activities,
                    isTaskRunning: isLoadingForCurrentConversation,
                    onSelectSwarm: { swarmId in
                        showSwarmPanel = true
                        selectedSwarmId = swarmId
                    }
                )
                if taskPanelEnabled {
                    if !taskActivityStore.concreteRecentActivities(limit: 1).isEmpty || !todoStore.todos.isEmpty {
                        TaskActivityPanel(
                            chatStore: chatStore,
                            taskActivityStore: taskActivityStore,
                            todoStore: todoStore,
                            conversationId: conversationId,
                            coderMode: coderMode,
                            debugPhase: debugStore.phase,
                            onOpenFile: { openFilesStore.openFile($0) },
                            effectivePrimaryPath: effectiveContext.primaryPath,
                            showTodoSection: shouldShowTaskPanelTodoSection
                        )
                    } else {
                        Text("No swarm activity available.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    Text("Swarm activity panel hidden.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: chatColumnMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appendComposerAttachments(_ incoming: [ComposerAttachment]) {
        guard !incoming.isEmpty else { return }
        var current = attachedComposerAttachments
        var seenPaths = Set(current.map { $0.url.standardizedFileURL.path })

        for item in incoming {
            guard current.count < AttachmentIntakeService.maxAttachmentsPerMessage else { break }
            if let size = item.sizeBytes, size > AttachmentIntakeService.maxAttachmentSizeBytes {
                continue
            }
            let path = item.url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                current.append(item)
            }
        }
        attachedComposerAttachments = current
    }

    private func handleAttachmentSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let hasHeic = urls.contains { ImageAttachmentHelper.isHeic(url: $0) }
            if hasHeic { isConvertingHeic = true }
            let imported = AttachmentIntakeService.importURLs(
                urls,
                existingCount: attachedComposerAttachments.count
            )
            appendComposerAttachments(imported.accepted)
            if hasHeic { isConvertingHeic = false }
        case .failure:
            break
        }
    }

    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isCmdShiftP(event) {
                cyclePlanShortcutState()
                return nil
            }
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isShiftTab(event) {
                handleShiftTabPlanShortcut()
                return nil
            }
            if showPlanPanel
                && event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.shift)
                && !event.modifierFlags.contains(.option)
                && !event.modifierFlags.contains(.control)
                && event.keyCode == 36 {
                NotificationCenter.default.post(name: Self.planBuildShortcutNotification, object: nil)
                return nil
            }
            // Cmd+Shift+D toggles debug panel
            let normalized = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if normalized.contains([.command, .shift]),
               !normalized.contains(.option),
               !normalized.contains(.control),
               event.charactersIgnoringModifiers?.lowercased() == "d" {
                debugToggleEnabled.toggle()
                return nil
            }
            guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v"
            else {
                return event
            }
            let attachments = AttachmentIntakeService.attachmentsFromPasteboard()
            if !attachments.isEmpty {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Self.attachmentPastedNotification,
                        object: nil,
                        userInfo: ["attachments": attachments]
                    )
                }
                return nil
            }
            return event
        }
    }

    private func isShiftTab(_ event: NSEvent) -> Bool {
        isShiftTabShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode
        )
    }

    private func isCmdShiftP(_ event: NSEvent) -> Bool {
        isCmdShiftPShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    private func removePasteMonitor() {
        if let m = pasteMonitor {
            NSEvent.removeMonitor(m)
            pasteMonitor = nil
        }
    }

    private func restorePlanStateIfNeeded(for conversationId: UUID?) {
        clearPlanStreamingState()
        let hasActiveTask = conversationId.map { activeBuildPlanConversationId == $0 || chatStore.isTaskActive(for: $0) } ?? false
        if !hasActiveTask {
            planClarificationCycles = 0
            planShouldRunInline = false
        }
        guard let conversationId else {
            planAnalysisContext = ""
            planUserRequest = ""
            planClarificationAnswers = ""
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        // If a plan build is actively running for this conversation, restore .building.
        // Don't clear plan context — the background task still needs it.
        if activeBuildPlanConversationId == conversationId {
            planFlowPhase = .building
            planningState = .idle
            return
        }
        // If a non-build task is active (e.g., plan generation phases 1–3),
        // preserve the current planFlowPhase — the running task manages it.
        if chatStore.isTaskActive(for: conversationId) {
            return
        }
        // No active flow — safe to reset per-flow context
        planAnalysisContext = ""
        planUserRequest = ""
        planClarificationAnswers = ""
        guard let board = chatStore.planBoard(for: conversationId) else {
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        let chosenPath = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasValidChosenPath =
            !chosenPath.isEmpty &&
            PlanOptionsParser.hasRequiredTodoHeader(chosenPath) &&
            !PlanOptionsParser.extractTodosFromOptionText(chosenPath).isEmpty
        if hasValidChosenPath {
            planFlowPhase = .readyToBuild
            planningState = .idle
            return
        }
        let compliantOptions = PlanOptionsParser.todoCompliantOptions(from: board.options)
        if !compliantOptions.isEmpty {
            let proposalContent: String
            if !chosenPath.isEmpty {
                proposalContent = chosenPath
            } else if let first = compliantOptions.min(by: { $0.id < $1.id })?.fullText,
                      !first.isEmpty {
                proposalContent = first
            } else {
                proposalContent = board.goal
            }
            planFlowPhase = .proposalReady
            planningState = .awaitingChoice(planContent: proposalContent, options: compliantOptions)
            return
        }
        planningState = .idle
        planFlowPhase = .idle
    }

    private func openPlanPanelForCurrentContext(
        preserveHistorySelection: Bool = false,
        source: PlanPanelPresentationSource = .manualDeepLink
    ) {
        planPanelPresentationSource = source
        if source == .automaticFlow || !preserveHistorySelection {
            planHistoryStore.setSelectedEntry(id: nil)
        }
        planShortcutPrimedUntil = nil
        showPlanPanel = true
    }

    private func cyclePlanShortcutState() {
        guard !isPlanShortcutCycling else { return }
        isPlanShortcutCycling = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                isPlanShortcutCycling = false
            }
        }

        let transition = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: planToggleEnabled,
            currentShowPlanPanel: showPlanPanel
        )
        let requestedPlanToggleOff = !transition.nextPlanToggleEnabled
        let canDeactivatePlanToggle = shouldAllowPlanToggleDeactivation(phase: planFlowPhase)
        let resolvedPlanToggleEnabled =
            requestedPlanToggleOff && !canDeactivatePlanToggle
            ? true
            : transition.nextPlanToggleEnabled
        withAnimation(.easeInOut(duration: 0.2)) {
            planToggleEnabled = resolvedPlanToggleEnabled
                if transition.nextShowPlanPanel {
                    openPlanPanelForCurrentContext(source: .manualShortcut)
                } else {
                    showPlanPanel = false
                    planShortcutPrimedUntil = nil
                    if requestedPlanToggleOff && canDeactivatePlanToggle {
                        planningState = .idle
                        planFlowPhase = .idle
                        clearPlanStreamingState()
                        planHistoryStore.setSelectedEntry(id: nil)
                    }
                }
            }
            isInputFocused = true
        }

    private func handleShiftTabPlanShortcut() {
        let now = Date()
        let transition = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: planShortcutPrimedUntil,
            currentInputText: inputText
        )

        inputText = transition.nextInputText
        planShortcutPrimedUntil = transition.nextPrimedUntil
        if transition.shouldEnablePlanToggle {
            planToggleEnabled = true
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPlanTabHovered = transition.shouldHighlightPlanToggle
        }

        if transition.shouldHighlightPlanToggle, let scheduledUntil = transition.nextPrimedUntil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                // Do not clear if a newer shortcut cycle has already updated the timer.
                if planShortcutPrimedUntil == scheduledUntil {
                    isPlanTabHovered = false
                }
            }
        }

        if transition.shouldFocusInput {
            isInputFocused = true
        }
    }

    private func downloadPlanEntry(_ entry: PlanHistoryEntry) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        let baseName = entry.title.isEmpty ? "PLAN" : entry.title
        savePanel.nameFieldStringValue = "\(baseName.replacingOccurrences(of: " ", with: "_")).md"
        let content = entry.markdown
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func copyWholeChatToClipboard() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        didCopyAllChat = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            didCopyAllChat = false
        }
    }

    private func downloadCurrentConversationMarkdown() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [Self.markdownExportContentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = chatStore.defaultMarkdownFilename(for: conversationId)
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func forkCurrentConversation() {
        guard let newConversationId = chatStore.forkConversation(from: conversationId) else { return }
        selectedConversationId = newConversationId
    }

    private func shouldHideBuildKickoffMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        guard suppressedEmptyBuildAssistantMessageIds.contains(message.id) else { return false }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    private var chatHeader: some View {
        ZStack {
            // Center: Mode tabs — Agent / IDE
            modeTabBar

            // Leading: project + (optional) title, Trailing: rewind button
            HStack(spacing: 8) {
                projectButton
                if shouldShowConversationTitle(headerWidth: chatHeaderWidth) {
                    conversationTitleLabel
                }
                Spacer(minLength: 0)
                rewindButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 32)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width) { _, w in chatHeaderWidth = w }
                    .onAppear { chatHeaderWidth = geo.size.width }
            }
        }
    }

    @ViewBuilder
    private var projectButton: some View {
        if let path = effectiveContext.primaryPath {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } label: {
                Text(effectiveContext.displayLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Open folder \(path)")
        }
    }

    private var conversationTitleLabel: some View {
        Text(chatStore.conversation(for: conversationId)?.title ?? "New conversation")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
    }

    private func shouldShowConversationTitle(headerWidth: CGFloat) -> Bool {
        // Hide thread title aggressively in narrow layouts to avoid overlap with centered mode tabs.
        headerWidth >= 720
    }

    private var rewindButton: some View {
        Button {
            rewindConversation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
                if isRewinding {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .foregroundStyle(
                (chatStore.canRewind(conversationId: conversationId) && !isLoadingForCurrentConversation
                    && !isRewinding) ? .secondary : .quaternary)
        }
        .buttonStyle(.plain)
        .disabled(
            !chatStore.canRewind(conversationId: conversationId) || isLoadingForCurrentConversation
                || isRewinding
        )
        .help("Rewind to previous checkpoint (restore chat and files)")
        .accessibilityLabel("Rewind checkpoint chat")
    }

    // MARK: - Mode Tab Bar (Agent / IDE)

    private var modeTabBar: some View {
        HStack(spacing: 2) {
            modeTabButton("Agent", icon: "brain", mode: .agent, color: DesignSystem.Colors.agentColor)
            modeTabButton("IDE", icon: "sparkles", mode: .ide, color: DesignSystem.Colors.ideColor)
            modeTabButton("Browser", icon: "globe", mode: .browser, color: DesignSystem.Colors.browserColor)
        }
    }

    private func modeTabButton(_ title: String, icon: String, mode: CoderMode, color: Color) -> some View {
        let isSelected = coderMode == mode || (mode == .agent && coderMode == .codeReviewMultiSwarm)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectMode(mode)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? color : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    /// Stable scroll anchor placed at the very bottom of the messages LazyVStack.
    /// Scrolling to this instead of individual message IDs avoids LazyVStack
    /// height-estimation thrashing that causes an infinite scroll-up loop
    /// when the conversation has more than one exchange.
    private let chatScrollTopAnchorId = "chat-scroll-top-anchor"
    private let chatScrollBottomAnchorId = "chat-scroll-bottom-anchor"

    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            messagesAreaScrollView(using: proxy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messagesAreaScrollView(using proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            chatMessagesAreaContent
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .overlay(messagesAreaEmptyStateOverlay)
        .onChange(of: streamContentVersion) { _, _ in
            handleStreamContentVersionChange(proxy: proxy)
        }
        .onChange(of: chatStore.conversation(for: conversationId)?.messages.count) { _, _ in
            handleMessagesCountChange(proxy: proxy)
        }
        .onChange(of: liveTraceEventCount) { _, _ in
            handleLiveTraceEventsChange(proxy: proxy)
        }
        .onChange(of: planningState) { _, new in
            handlePlanningStateChange(new, proxy: proxy)
        }
        .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
            handleActiveTaskConversationChange(oldSet: oldSet, newSet: newSet, proxy: proxy)
        }
        .onChange(of: taskActivityStore.activities.count) { _, _ in
            handleTaskActivitiesChange(proxy: proxy)
        }
        .simultaneousGesture(
            // Keep this low so trackpad/mouse-wheel scrolling detaches live-follow
            // quickly and prevents forced jumps back to the latest trace event.
            DragGesture(minimumDistance: 2).onChanged { _ in
                if isLoadingForCurrentConversation {
                    isFollowingLive = false
                }
            },
            including: isLoadingForCurrentConversation ? .gesture : .subviews
        )
        .overlay(alignment: .bottomTrailing) {
            messagesAreaFloatingScrollButtons(using: proxy)
        }
    }

    @ViewBuilder
    private var messagesAreaEmptyStateOverlay: some View {
        if messagesAreaIsEmpty && !isLoadingForCurrentConversation {
            VStack(spacing: 20) {
                if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
                   let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .cornerRadius(13)
                        .saturation(0)
                        .opacity(0.3)
                }
                VStack(spacing: 6) {
                    Text("codigo")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.45))
                    Text("Ask anything, build anything")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
            .allowsHitTesting(false)
        }
    }

    private var messagesAreaIsEmpty: Bool {
        guard let conv = chatStore.conversation(for: conversationId) else { return true }
        return conv.messages.isEmpty
    }

    @ViewBuilder
    private func messagesAreaFloatingScrollButtons(using proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if !messagesAreaIsEmpty && (!isFollowingLive || isLoadingForCurrentConversation) {
                Button {
                    isFollowingLive = false
                    scheduleAutoScroll(
                        proxy: proxy,
                        target: chatScrollTopAnchorId,
                        animated: true,
                        delay: 0
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Torna su")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        DesignSystem.Colors.backgroundSecondary.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !isFollowingLive && isLoadingForCurrentConversation {
                Button {
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    if let target = liveScrollTarget() {
                        scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                    }
                    taskActivityStore.markLiveEventsSeen()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back to live")
                            .font(.system(size: 11, weight: .semibold))
                        if newEventsWhileDetached > 0 {
                            Text("\(newEventsWhileDetached)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        DesignSystem.Colors.backgroundSecondary.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 10)
    }

    private func handleStreamContentVersionChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.016)
    }

    private func handleMessagesCountChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, animated: true, delay: 0.05)
    }

    private func handleLiveTraceEventsChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.02)
        }
    }

    private func handlePlanningStateChange(_ newState: PlanningState, proxy: ScrollViewProxy) {
        if case .awaitingChoice = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        } else if case .awaitingClarification = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        }
    }

    private func handleActiveTaskConversationChange(
        oldSet: Set<UUID>,
        newSet: Set<UUID>,
        proxy: ScrollViewProxy
    ) {
        guard let cid = conversationId else { return }
        let isActive = newSet.contains(cid)
        let wasActive = oldSet.contains(cid)
        if !wasActive && isActive {
            isFollowingLive = true
            newEventsWhileDetached = 0
            if let target = liveScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
            }
        } else if wasActive && !isActive {
            cancelFallbackTurnStartEvent()
            isFollowingLive = true
            newEventsWhileDetached = 0
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0.16)
            }
        }
    }

    private func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        if isLoadingForCurrentConversation {
            if isFollowingLive {
                if let target = liveScrollTarget() {
                    scheduleAutoScroll(proxy: proxy, target: target)
                }
            } else {
                newEventsWhileDetached += 1
            }
        }
    }

    @ViewBuilder
    private var chatMessagesAreaContent: some View {
        if let conv = chatStore.conversation(for: conversationId) {
            messagesStack(for: conv)
        }
    }

    @ViewBuilder
    private func messagesStack(for conv: Conversation) -> some View {
        let convId = conv.id
        let messages = conv.messages
        let lastMsg = messages.last
        let hasPersistentPlanCard = messages.contains { $0.planAttachment != nil }
        let latestAssistantMessageId = messages.last(where: { $0.role == .assistant })?.id
        let messageIndexById: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: messages.enumerated().map { ($0.element.id, $0.offset) }
        )
        LazyVStack(alignment: .leading, spacing: 28) {
            Color.clear
                .frame(height: 1)
                .id(chatScrollTopAnchorId)
            ForEach(messages, id: \.id) { message in
                let index = messageIndexById[message.id] ?? 0
                chatMessageCell(
                    message: message,
                    index: index,
                    lastMsg: lastMsg,
                    latestAssistantMessageId: latestAssistantMessageId,
                    conversationId: convId
                )
            }
            if shouldShowInlinePlanSummaryInChat,
               coderMode == .agent,
               !hasPersistentPlanCard,
               let cid = conversationId,
               let summary = inlinePlanSummaries[cid]
            {
                PlanSummaryCardView(
                    title: summary.title,
                    summaryMarkdown: summary.body,
                    isCollapsed: isPlanSummaryCollapsed,
                    onToggleCollapse: { isPlanSummaryCollapsed.toggle() },
                    onExpandPlan: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            openPlanPanelForCurrentContext(source: .manualDeepLink)
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .id("plan-summary-card")
            }
            if shouldShowPlanBoardInChat, let board = chatStore.planBoard(for: conversationId) {
                PlanBoardView(
                    board: board,
                    onSelectOption: { selectPlanChoice($0.fullText) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .id("plan-board")
            }
            // Invisible anchor at the very bottom – scrollTo targets this
            // instead of a message id so that LazyVStack doesn't thrash
            // height estimates for off-screen items.
            Color.clear
                .frame(height: 1)
                .id(chatScrollBottomAnchorId)
        }
    }

    @ViewBuilder
    private func chatMessageCell(
        message: ChatMessage,
        index: Int,
        lastMsg: ChatMessage?,
        latestAssistantMessageId: UUID?,
        conversationId: UUID
    ) -> some View {
        let isLast = message.id == lastMsg?.id
        let isLastAssistant = lastMsg?.role == .assistant && isLast
        let userMessageCheckpoint = message.role == .user
            ? chatStore.checkpoint(forMessageIndex: index, conversationId: conversationId)
            : nil
        let hasCheckpointForMessage = userMessageCheckpoint != nil
        let canRewindFromMessage = message.role == .user && !isRewinding
        let needsDivider = message.role == .user && index > 0
        let restoreAction: (() -> Void)? = message.role == .user
            ? { rewindToMessage(at: index, conversationId: conversationId) }
            : nil
        let replyAction: (() -> Void)? = message.role == .assistant
            ? { beginReply(to: message) }
            : nil
        let deleteAction: (() -> Void)? = message.role == .assistant
            ? { chatStore.removeMessage(messageId: message.id, in: conversationId) }
            : nil

        if shouldHideBuildKickoffMessage(message) {
            EmptyView()
                .id(message.id)
        } else {
            HStack(alignment: .top, spacing: 0) {
                if message.role == .user { Spacer(minLength: 0) }
                if shouldShowPlanAttachmentsInChat,
                   message.role == .assistant,
                   let attachment = message.planAttachment,
                   let entry = planHistoryStore.findEntry(id: attachment.historyEntryId)
                {
                    PlanChatCardView(
                        entry: entry,
                        onDownload: { downloadPlanEntry(entry) },
                        onDuplicate: { _ = planHistoryStore.duplicateEntry(id: entry.id) },
                        onRebuild: {
                            let choice = (entry.chosenPath?.isEmpty == false)
                                ? (entry.chosenPath ?? entry.markdown)
                                : entry.markdown
                            executeWithPlanChoice(
                                choice,
                                fromPlanConversationId: entry.conversationId
                            )
                            planHistoryStore.markRebuilt(id: entry.id)
                        },
                        onOpenInPanel: {
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: true,
                                source: .manualDeepLink
                            )
                        },
                        onRemove: { planHistoryStore.deleteEntry(id: entry.id) },
                        onExpandPlan: {
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: true,
                                source: .manualDeepLink
                            )
                        }
                    )
                } else {
                    let isLiveReasoningTarget = conversationId == streamingReasoningConversationId
                        && isLastAssistant
                        && message.isStreaming
                    let effectiveReasoning: String? = {
                        if isLiveReasoningTarget {
                            return streamingReasoningText
                        }
                        return message.reasoningText
                    }()
                    let effectiveReasoningBlocks: [ReasoningBlock] = {
                        if isLiveReasoningTarget {
                            return streamingReasoningBlocks
                        }
                        return []
                    }()
                    let suppressPlanArtifacts = shouldSuppressPlanArtifactsInChat(
                        message: message,
                        conversationId: conversationId
                    )
                    let displayMessage = suppressPlanArtifacts
                        ? chatDisplayMessage(from: message, conversationId: conversationId)
                        : message
                    let shouldHideStreamingBarOnPreviousAssistant =
                        message.role == .assistant
                        && !isLastAssistant
                        && lastMsg?.role == .assistant
                        && (lastMsg?.isStreaming ?? false)
                        && isLoadingForCurrentConversation
                    let useSequentialLayout = isLiveReasoningTarget && !streamingSegments.isEmpty
                    VStack(alignment: .leading, spacing: 10) {
                        if useSequentialLayout {
                            sequentialSegmentedContent(
                                message: displayMessage,
                                segments: streamingSegments,
                                effectiveContext: effectiveContext,
                                suppressPlanArtifacts: suppressPlanArtifacts,
                                shouldHideStreamingBar: shouldHideStreamingBarOnPreviousAssistant,
                                restoreAction: restoreAction,
                                replyAction: replyAction,
                                deleteAction: deleteAction,
                                canRewindFromMessage: canRewindFromMessage,
                                hasCheckpointForMessage: hasCheckpointForMessage,
                                needsDivider: needsDivider,
                                latestAssistantMessageId: latestAssistantMessageId,
                                conversationId: conversationId
                            )
                        } else {
                            MessageRow(
                                message: displayMessage,
                                context: effectiveContext.context,
                                modeColor: activeModeColor,
                                isActuallyLoading: isLoadingForCurrentConversation,
                                streamingStatusText: streamingStatusText(for: displayMessage),
                                streamingDetailText: streamingDetailText(for: displayMessage, conversationId: conversationId),
                                streamingReasoningText: effectiveReasoning,
                                streamingReasoningBlocks: effectiveReasoningBlocks,
                                showStreamingBar: !shouldHideStreamingBarOnPreviousAssistant,
                                onFileClicked: { openFilesStore.openFile($0) },
                                onRestoreCheckpoint: restoreAction,
                                onReply: replyAction,
                                onDelete: deleteAction,
                                canRewind: canRewindFromMessage,
                                hasCheckpointForRestore: hasCheckpointForMessage,
                                showTopDivider: needsDivider
                            )
                            if message.role == .assistant {
                                if shouldShowPlanTodosInChat,
                                   !todoStore.todos.isEmpty,
                                   message.id == latestAssistantMessageId
                                {
                                    TodoLiveInlineCard(
                                        store: todoStore,
                                        onOpenFile: { openFilesStore.openFile($0) }
                                    )
                                    .padding(.horizontal, 2)
                                }
                                let traceEvents = toolTraceStore.events(
                                    conversationId: conversationId,
                                    assistantMessageId: message.id
                                )
                                if !traceEvents.isEmpty {
                                    messageTraceView(
                                        traceEvents: traceEvents,
                                        effectiveContext: effectiveContext
                                    )
                                }
                            }
                        }
                    }
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }
            .id(message.id)
        }
    }

    @ViewBuilder
    private func sequentialSegmentedContent(
        message: ChatMessage,
        segments: [MessageSegment],
        effectiveContext: EffectiveContext,
        suppressPlanArtifacts: Bool,
        shouldHideStreamingBar: Bool,
        restoreAction: (() -> Void)?,
        replyAction: (() -> Void)?,
        deleteAction: (() -> Void)?,
        canRewindFromMessage: Bool,
        hasCheckpointForMessage: Bool,
        needsDivider: Bool,
        latestAssistantMessageId: UUID?,
        conversationId: UUID
    ) -> some View {
        let contentMaxWidth: CGFloat = 800
        let isStreaming = message.isStreaming && isLoadingForCurrentConversation

        if needsDivider {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.0),
                            Color.primary.opacity(0.06),
                            Color.primary.opacity(0.06),
                            Color.primary.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .frame(maxWidth: 860)
                .padding(.bottom, 20)
        }

        HStack(spacing: 5) {
            Circle()
                .fill(activeModeColor.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
            Text("Codigo")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 5)

        ForEach(segments) { segment in
            switch segment.kind {
            case .reasoning(let text):
                ThinkingBlockView(text: text, isLiveStreaming: isStreaming)
                    .padding(.bottom, 4)
            case .text(let content):
                if !content.isEmpty {
                    MarkdownContentView(
                        content: content,
                        context: effectiveContext.context,
                        onFileClicked: { openFilesStore.openFile($0) },
                        textAlignment: .leading,
                        isStreaming: isStreaming
                    )
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(.vertical, 4)
                }
            case .toolTrace(let events):
                if !events.isEmpty {
                    messageTraceView(
                        traceEvents: events,
                        effectiveContext: effectiveContext
                    )
                }
            }
        }

        if isStreaming, !shouldHideStreamingBar {
            let status = streamingStatusText(for: message).isEmpty ? "Thinking" : streamingStatusText(for: message)
            HStack(spacing: 6) {
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textShimmer(active: true)
                if status != "Planning next move",
                   let detail = streamingDetailText(for: message, conversationId: conversationId),
                   !detail.isEmpty
                {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textShimmer(active: true)
                }
                Spacer()
            }
            .padding(.top, 2)
        }

        if shouldShowPlanTodosInChat,
           !todoStore.todos.isEmpty,
           message.id == latestAssistantMessageId
        {
            TodoLiveInlineCard(
                store: todoStore,
                onOpenFile: { openFilesStore.openFile($0) }
            )
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var finalChatActionsBar: some View {
        let conv = chatStore.conversation(for: conversationId)
        let messageCount = conv?.messages.count ?? 0
        let assistantCount = conv?.messages.filter { $0.role == .assistant }.count ?? 0
        let userCount = conv?.messages.filter { $0.role == .user }.count ?? 0
        let latestAssistantMessageId = conv?.messages.last(where: { $0.role == .assistant })?.id
        let traceEvents = {
            guard let c = conv, let assistantId = latestAssistantMessageId else { return [ToolTraceEvent]() }
            return toolTraceStore.events(conversationId: c.id, assistantMessageId: assistantId)
        }()
        let editCount = traceEvents.filter { ToolTraceFileChangeMapper.isFileChangeEvent($0) }.count
        let fileChanges = ToolTraceFileChangeMapper.collect(from: traceEvents)
        let linesAdded = fileChanges.reduce(0) { $0 + max(0, $1.added) }
        let linesRemoved = fileChanges.reduce(0) { $0 + max(0, $1.removed) }

        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeModeColor.opacity(0.0),
                            activeModeColor.opacity(0.12),
                            activeModeColor.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 40)

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeModeColor.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text("Task completed")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.2)
                }

                if messageCount > 0 {
                    HStack(spacing: 16) {
                        finalStatPill(
                            icon: "bubble.left.and.bubble.right",
                            value: "\(userCount + assistantCount)",
                            label: "messages"
                        )
                        if editCount > 0 {
                            finalStatPill(
                                icon: "pencil",
                                value: "\(editCount)",
                                label: editCount == 1 ? "edit" : "edits"
                            )
                        }
                        if fileChanges.count > 0 {
                            finalStatPill(
                                icon: "doc.text",
                                value: "\(fileChanges.count)",
                                label: fileChanges.count == 1 ? "file" : "files"
                            )
                        }
                        if linesAdded > 0 || linesRemoved > 0 {
                            HStack(spacing: 4) {
                                Text("+\(linesAdded)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
                                Text("-\(linesRemoved)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    finalChatActionButton(
                        icon: didCopyAllChat ? "checkmark" : "doc.on.doc",
                        title: didCopyAllChat ? "Copied" : "Copy all",
                        help: didCopyAllChat ? "Copied" : "Copy entire chat as Markdown",
                        foreground: didCopyAllChat ? DesignSystem.Colors.success : .secondary,
                        action: copyWholeChatToClipboard
                    )
                    finalChatActionButton(
                        icon: "arrow.down.to.line",
                        title: "Export",
                        help: "Download chat as Markdown",
                        foreground: .secondary,
                        action: downloadCurrentConversationMarkdown
                    )
                    finalChatActionButton(
                        icon: "arrow.triangle.branch",
                        title: "Fork",
                        help: "Fork this chat into a new thread",
                        foreground: .secondary,
                        action: forkCurrentConversation
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }

    private func finalStatPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.quaternary)
        }
    }

    private func finalChatActionButton(
        icon: String,
        title: String,
        help: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    private func enableTaskPanelIfNeeded() {
        guard shouldEnableTaskPanelForMode(coderMode) else { return }
        if !taskPanelEnabled {
            taskPanelEnabled = true
        }
    }

    private func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        fallbackTurnStartWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                guard chatStore.isTaskActive(for: conversationId) else { return }
                guard taskActivityStore.activities.isEmpty else { return }
                recordTaskActivity(
                    type: "turn_started",
                    payload: [
                        "title": "Turn started",
                        "detail": "Request execution in progress",
                        "status": "started",
                        "group_id": "ui-fallback-\(conversationId.uuidString)",
                    ],
                    providerId: providerId,
                    conversationId: conversationId
                )
            }
        }
        fallbackTurnStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelFallbackTurnStartEvent() {
        fallbackTurnStartWorkItem?.cancel()
        fallbackTurnStartWorkItem = nil
    }

    private func liveScrollTarget() -> AnyHashable? {
        guard isLoadingForCurrentConversation else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    private var liveTraceEventCount: Int {
        guard let conv = chatStore.conversation(for: conversationId),
              let lastAssistant = conv.messages.last(where: { $0.role == .assistant }) else {
            return 0
        }
        return toolTraceStore.events(
            conversationId: conv.id,
            assistantMessageId: lastAssistant.id
        ).count
    }

    @ViewBuilder
    private func subagentCardsSection(message: ChatMessage, isLatestAssistant: Bool) -> some View {
        let liveCards: [SwarmLiveCardState] = (isLatestAssistant && isLoadingForCurrentConversation)
            ? visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates())
            : []
        let hasLiveCards = !liveCards.isEmpty

        if hasLiveCards {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(liveCards) { card in
                    SubagentChatCardView(
                        card: card,
                        onOpenInPanel: {
                            selectedSwarmId = card.swarmId
                            showSwarmPanel = true
                        },
                        onStop: {
                            lastTaskEndedByManualStop = true
                            interruptTask()
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        // Show persisted snapshot cards when live cards aren't available.
        // This avoids a gap where neither live nor snapshot cards are visible.
        if !hasLiveCards, let snapshots = message.subagentCards, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshots) { snapshot in
                    SubagentSnapshotCardView(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func messageTraceView(
        traceEvents: [ToolTraceEvent],
        effectiveContext: EffectiveContext
    ) -> some View {
        MessageToolTraceView(
            events: traceEvents,
            workspaceHints: traceWorkspaceHints(for: effectiveContext),
            onOpenFile: { openFilesStore.openFile($0) },
            onInteractionStart: {
                guard isLoadingForCurrentConversation else { return }
                isFollowingLive = false
            }
        )
    }

    private func traceWorkspaceHints(for effectiveContext: EffectiveContext) -> [String] {
        let fromContext = effectiveContext.context?.folderPaths
            .filter { !$0.isEmpty } ?? []
        if !fromContext.isEmpty {
            return fromContext
        }
        if let primary = effectiveContext.primaryPath, !primary.isEmpty {
            return [primary]
        }
        return []
    }

    private func latestMessageScrollTarget() -> AnyHashable? {
        guard chatStore.conversation(for: conversationId)?.messages.last != nil else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    private func scheduleAutoScroll(
        proxy: ScrollViewProxy,
        target: AnyHashable,
        animated: Bool = false,
        delay: TimeInterval = 0.08
    ) {
        let now = Date()
        let sinceLastScroll = now.timeIntervalSince(lastAutoScrollAt)
        if lastAutoScrollTarget == target, sinceLastScroll < 0.04 {
            return
        }
        lastAutoScrollTarget = target
        lastAutoScrollAt = now
        autoScrollWorkItem?.cancel()
        let effectiveDelay = sinceLastScroll < 0.1 ? min(delay, 0.03) : delay
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
        autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: work)
    }

    private func interruptTask() {
        interruptTask(for: conversationId)
    }

    @MainActor
    private func launchRunTask(
        for conversationId: UUID,
        operation: @escaping () async -> Void
    ) {
        activeRunTaskByConversation[conversationId]?.cancel()
        let token = UUID()
        activeRunTokenByConversation[conversationId] = token

        let task = Task { @MainActor in
            await operation()
            guard activeRunTokenByConversation[conversationId] == token else { return }
            activeRunTokenByConversation.removeValue(forKey: conversationId)
            activeRunTaskByConversation.removeValue(forKey: conversationId)
        }
        activeRunTaskByConversation[conversationId] = task
    }

    @MainActor
    @discardableResult
    private func cancelRunTask(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let task = activeRunTaskByConversation[conversationId] else { return false }
        task.cancel()
        activeRunTaskByConversation.removeValue(forKey: conversationId)
        activeRunTokenByConversation.removeValue(forKey: conversationId)
        return true
    }

    @MainActor
    private func applyFlowCoordinatorState(
        for targetConversationId: UUID?,
        _ transition: (ConversationFlowCoordinator) -> Void
    ) {
        guard targetConversationId == conversationId else { return }
        transition(flowCoordinator)
    }

    /// Snapshots current swarm cards into the last assistant message, then ends the task.
    /// Flushes pending streaming content first to ensure no data is lost.
    @MainActor
    private func snapshotSubagentCardsAndEndTask(conversationId targetConversationId: UUID?) {
        // Flush any pending streamed content so the assistant message is up-to-date
        // before we attach subagent cards or end the task.
        flushStreamingContent()

        // Flush pending task activities so subagent swarm cards are fully
        // populated before we snapshot them into the assistant message.
        flushPendingTaskActivities()
        taskActivityStore.flushPending()

        // Transition any cards still stuck in .running to .completed
        // so the panel doesn't show stale running indicators.
        taskActivityStore.finalizeRunningSwarmCards()

        let cards = visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates())
            .map { SubagentCardSnapshot(from: $0) }
        if !cards.isEmpty {
            chatStore.saveSubagentCardsToLastAssistant(cards, in: targetConversationId)
        }
        chatStore.endTask(conversationId: targetConversationId)
        // Force immediate persistence so the final state (cards + content)
        // survives an app crash right after task completion.
        chatStore.saveConversationsImmediately()
    }

    private func visibleSwarmCardsForChat(from cards: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        return cards
    }

    private func interruptTask(for targetConversationId: UUID?) {
        var didCancelTask = cancelRunTask(for: targetConversationId)
        if !didCancelTask, let target = targetConversationId,
           activeBuildPlanConversationId == target,
           let agentId = activeBuildAgentConversationId {
            didCancelTask = cancelRunTask(for: agentId)
        }
        if !didCancelTask {
            let scope = executionScopeForCurrentMode()
            executionController.terminate(scope: scope)
        }
        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let cid = targetConversationId {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrupted by user]"
                    : cur + "\n\n[Interrupted by user]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
            clearStreamingReasoning(for: cid)
        }
        finalizeToolTraceTurn(conversationId: targetConversationId, outcome: .aborted)
        if targetConversationId == conversationId {
            cancelFallbackTurnStartEvent()
        }
        snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        if activeBuildPlanConversationId == targetConversationId {
            activeBuildPlanConversationId = nil
        }
        if targetConversationId == conversationId {
            resetPlanFlowAfterInterruption()
        }
    }

    private func resetPlanFlowAfterInterruption() {
        switch planFlowPhase {
        case .building:
            planFlowPhase = .readyToBuild
            clearPlanStreamingState()
        case .proposalReady:
            break
        case .analyzing, .questioning, .generating:
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        default:
            break
        }
    }

    private func executionScopeForCurrentMode() -> ExecutionScope {
        switch coderMode {
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    private func pauseOrResumeActiveTask() {
        let scope = executionScopeForCurrentMode()
        if executionController.runState == .paused {
            executionController.resume(scope: scope)
            taskActivityStore.markResumed()
            taskActivityStore.addActivity(
                TaskActivity(
                    type: "process_resumed",
                    title: "Process resumed",
                    detail: "Execution resumed by user",
                    payload: [:],
                    phase: .executing,
                    isRunning: true
                )
            )
            return
        }

        executionController.pause(scope: scope)
        taskActivityStore.markPaused()
        taskActivityStore.addActivity(
            TaskActivity(
                type: "process_paused",
                title: "Process paused",
                detail: "Execution paused by user",
                payload: [:],
                phase: .planning,
                isRunning: false
            )
        )
    }

    private func handleVoiceAction() {
        if isLoadingForCurrentConversation {
            return
        }
        switch voiceInputController.state {
        case .idle, .failed:
            voiceInputController.start { transcript in
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = trimmed
                } else {
                    inputText = inputText + (inputText.hasSuffix(" ") ? "" : " ") + trimmed
                }
                isInputFocused = true
            }
        case .listening:
            voiceInputController.stop()
        case .requestingPermission, .transcribing:
            break
        }
    }

    private func currentInstructionPolicyBundle() -> InstructionPolicyBundle {
        let hints = traceWorkspaceHints(for: effectiveContext)
        return InstructionPolicyBundle.load(workspacePaths: hints)
    }

    private func expectedPolicyAckHash() -> String? {
        guard agentsHardBlockEnabled else { return nil }
        let bundle = currentInstructionPolicyBundle()
        let hash = bundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }
        return hash
    }

    private func initializePolicyAckStateIfNeeded(for assistantMessageId: UUID) {
        guard let expectedHash = expectedPolicyAckHash() else {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
            return
        }
        guard !policyAckFailedMessages.contains(assistantMessageId) else { return }
        if policyAckStateByMessage[assistantMessageId] == nil {
            policyAckStateByMessage[assistantMessageId] = PolicyAckState(expectedHash: expectedHash)
        }
    }

    @MainActor
    private func startToolTraceTurn(conversationId: UUID, assistantMessageId: UUID, providerId: String) {
        if let previous = activeToolTraceTurnsByConversation[conversationId],
           previous.assistantMessageId != assistantMessageId {
            let previousEvents = toolTraceStore.events(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            let hasRunningOperations = previousEvents.contains(where: \.isRunning)
            let rolloverOutcome: ToolTraceTurnOutcome = hasRunningOperations ? .aborted : .success
            finalizeAutoTodoIfNeeded(
                messageId: previous.assistantMessageId,
                outcome: rolloverOutcome,
                providerId: previous.providerId,
                conversationId: previous.conversationId
            )
            toolTraceStore.finalizeTurn(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            toolTraceNextSequenceByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalSeenByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalCountByMessage.removeValue(forKey: previous.assistantMessageId)
            policyAckStateByMessage.removeValue(forKey: previous.assistantMessageId)
            // Flush any remaining blocked events before discarding the queue
            if let remainingQueued = policyAckBlockedQueue.removeValue(forKey: previous.assistantMessageId), !remainingQueued.isEmpty {
                if !policyAckFailedMessages.contains(previous.assistantMessageId) {
                    for event in remainingQueued {
                        recordTaskActivity(
                            type: event.type,
                            payload: event.payload,
                            providerId: event.providerId,
                            conversationId: event.conversationId
                        )
                    }
                }
            }
            policyAckFailedMessages.remove(previous.assistantMessageId)
            autoTodoIdByMessage.removeValue(forKey: previous.assistantMessageId)
            autoTodoCompletedOperationsByMessage.removeValue(forKey: previous.assistantMessageId)
            didReceiveExplicitTodoByMessage.remove(previous.assistantMessageId)
        }
        let turn = ToolTraceTurnContext(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurnsByConversation[conversationId] = turn
        toolTraceNextSequenceByMessage[assistantMessageId] = 1
        toolTraceOperationalSeenByMessage[assistantMessageId] = false
        toolTraceOperationalCountByMessage[assistantMessageId] = 0
        autoTodoIdByMessage.removeValue(forKey: assistantMessageId)
        autoTodoCompletedOperationsByMessage.removeValue(forKey: assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(assistantMessageId)
        if isSwarmPolicyAckExemptProvider(providerId) {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
    }

    @MainActor
    private func finalizeToolTraceTurn(conversationId: UUID?, outcome: ToolTraceTurnOutcome? = nil) {
        let finalOutcome = outcome ?? toolTraceTurnOutcome(for: flowCoordinator.state)

        if let conversationId {
            guard let active = activeToolTraceTurnsByConversation[conversationId] else { return }
            finalizeToolTraceTurn(active, outcome: finalOutcome)
            activeToolTraceTurnsByConversation.removeValue(forKey: conversationId)
            return
        }

        let activeTurns = Array(activeToolTraceTurnsByConversation.values)
        for active in activeTurns {
            finalizeToolTraceTurn(active, outcome: finalOutcome)
        }
        activeToolTraceTurnsByConversation.removeAll()
    }

    @MainActor
    private func finalizeToolTraceTurn(
        _ active: ToolTraceTurnContext,
        outcome: ToolTraceTurnOutcome
    ) {
        finalizeAutoTodoIfNeeded(
            messageId: active.assistantMessageId,
            outcome: outcome,
            providerId: active.providerId,
            conversationId: active.conversationId
        )
        toolTraceStore.finalizeTurn(
            conversationId: active.conversationId,
            assistantMessageId: active.assistantMessageId
        )
        toolTraceNextSequenceByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalSeenByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalCountByMessage.removeValue(forKey: active.assistantMessageId)
        policyAckStateByMessage.removeValue(forKey: active.assistantMessageId)
        policyAckBlockedQueue.removeValue(forKey: active.assistantMessageId)
        autoTodoIdByMessage.removeValue(forKey: active.assistantMessageId)
        autoTodoCompletedOperationsByMessage.removeValue(forKey: active.assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(active.assistantMessageId)
    }

    @MainActor
    private func finalizeAutoTodoIfNeeded(
        messageId: UUID,
        outcome: ToolTraceTurnOutcome,
        providerId: String,
        conversationId: UUID
    ) {
        if let autoTodoId = autoTodoIdByMessage[messageId],
           !didReceiveExplicitTodoByMessage.contains(messageId) {
            let finalStatus = autoTodoFinalStatus(for: outcome)
            todoStore.setStatus(id: autoTodoId, status: finalStatus)
            let currentTodo = todoStore.todos.first(where: { $0.id == autoTodoId })
            let notes: String = {
                switch finalStatus {
                case .done:
                    return "Auto-generated: all trace activities completed."
                case .blocked:
                    return "Auto-generated: execution interrupted or failed."
                default:
                    return "Auto-generated: status updated."
                }
            }()
            emitAutoTodoTraceUpdate(
                todoId: autoTodoId,
                title: currentTodo?.title ?? "Auto TODO",
                status: finalStatus,
                notes: notes,
                linkedFiles: currentTodo?.linkedFiles ?? [],
                providerId: providerId,
                conversationId: conversationId,
                timestamp: .now
            )
        }
    }

    @MainActor
    private func resolveToolTraceTurn(conversationId: UUID?, providerId: String) -> ToolTraceTurnContext? {
        let activeTarget = conversationId.flatMap { id in
            activeToolTraceTurnsByConversation[id].map {
                ToolTraceBindingTarget(
                    conversationId: $0.conversationId,
                    assistantMessageId: $0.assistantMessageId
                )
            }
        }
        let fallbackAssistantMessageId = conversationId.flatMap { id in
            chatStore.conversation(for: id)?
                .messages
                .last(where: { $0.role == .assistant })?
                .id
        }
        guard let target = ToolTraceBindingResolver.resolve(
            activeTurn: activeTarget,
            requestedConversationId: conversationId,
            fallbackAssistantMessageId: fallbackAssistantMessageId
        ) else {
            return nil
        }
        let fallbackTurn = ToolTraceTurnContext(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        if toolTraceNextSequenceByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            let next = (existing.last?.sequence ?? 0) + 1
            toolTraceNextSequenceByMessage[target.assistantMessageId] = max(1, next)
        }
        if toolTraceOperationalSeenByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalSeenByMessage[target.assistantMessageId] = existing.contains {
                isOperationalTraceEvent($0)
            }
        }
        if toolTraceOperationalCountByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalCountByMessage[target.assistantMessageId] = existing.reduce(into: 0) { partial, event in
                if isOperationalTraceEvent(event) {
                    partial += 1
                }
            }
        }
        if isSwarmPolicyAckExemptProvider(providerId) {
            policyAckStateByMessage.removeValue(forKey: target.assistantMessageId)
            policyAckFailedMessages.remove(target.assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: target.assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurnsByConversation[target.conversationId] = fallbackTurn
        return fallbackTurn
    }

    @MainActor
    private func appendToolTraceEvent(
        activity: TaskActivity,
        rawKind: EventKind,
        providerId: String,
        conversationId: UUID?
    ) {
        guard ToolTraceVisibility.shouldInclude(activity: activity) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let sequence = toolTraceNextSequenceByMessage[turn.assistantMessageId] ?? 1
        let event = ToolTraceEvent(
            sequence: sequence,
            timestamp: activity.timestamp,
            providerId: providerId,
            conversationId: turn.conversationId,
            assistantMessageId: turn.assistantMessageId,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: activity.payload,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId,
            rawKind: rawKind.rawValue
        )
        toolTraceStore.append(event: event)
        toolTraceNextSequenceByMessage[turn.assistantMessageId] = sequence + 1
        if isOperationalTraceActivity(activity) {
            toolTraceOperationalSeenByMessage[turn.assistantMessageId] = true
            let current = toolTraceOperationalCountByMessage[turn.assistantMessageId] ?? 0
            toolTraceOperationalCountByMessage[turn.assistantMessageId] = current + 1
        }
        updateStreamingToolSegment(newEvent: event, conversationId: turn.conversationId, assistantMessageId: turn.assistantMessageId)
    }

    private func updateStreamingToolSegment(
        newEvent: ToolTraceEvent,
        conversationId: UUID,
        assistantMessageId: UUID
    ) {
        guard conversationId == self.conversationId else { return }
        let segId = "tools-\(streamingSegmentTurnIndex)"
        if let idx = streamingSegments.firstIndex(where: { $0.id == segId }) {
            if case .toolTrace(var existing) = streamingSegments[idx].kind {
                if let updateIdx = existing.firstIndex(where: { $0.id == newEvent.id }) {
                    existing[updateIdx] = newEvent
                } else {
                    existing.append(newEvent)
                }
                streamingSegments[idx].kind = .toolTrace(existing)
            }
        } else {
            streamingSegments.append(MessageSegment(id: segId, kind: .toolTrace([newEvent])))
        }
    }

    @MainActor
    private func recordTaskActivity(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) {
        cancelFallbackTurnStartEvent()
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                let scopedActivity = activityWithConversationContext(
                    activity,
                    conversationId: conversationId
                )
                ensureAutoTodoStartedBeforeOperationalActivity(
                    activity: scopedActivity,
                    providerId: providerId,
                    conversationId: conversationId
                )
                enqueueTaskActivity(scopedActivity)
                appendToolTraceEvent(
                    activity: scopedActivity,
                    rawKind: envelope.kind,
                    providerId: providerId,
                    conversationId: conversationId
                )
                updateAutoTodoProgressAfterOperationalActivity(
                    activity: scopedActivity,
                    providerId: providerId,
                    conversationId: conversationId
                )
            case .instantGrep(let grep):
                enableTaskPanelIfNeeded()
                pendingInstantGreps.append(grep)
                logTaskBacklogIfNeeded(context: "enqueue_grep")
                scheduleTaskActivityFlush()
            case .todoWrite(let todo):
                guard shouldAcceptTodoWrite(todo, conversationId: conversationId) else { break }
                enableTaskPanelIfNeeded()
                if isPlanBuildContext(
                    conversationId: conversationId,
                    phase: planFlowPhase,
                    activeBuildPlanConversationId: activeBuildPlanConversationId,
                    activeBuildAgentConversationId: activeBuildAgentConversationId
                ) {
                    let updated = todoStore.upsertCanonicalOnlyFromAgent(
                        id: todo.id,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        activeForm: todo.activeForm,
                        linkedFiles: todo.files
                    )
                    if updated {
                        let canonicalTodos = todoStore.todos.filter(\.isPlanCanonical)
                        if let sourcePlanId = activeBuildPlanConversationId {
                            chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: sourcePlanId)
                        }
                    }
                } else {
                    todoStore.upsertFromAgent(
                        id: todo.id,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        activeForm: todo.activeForm,
                        linkedFiles: todo.files
                    )
                }
                recordExplicitTodoWrite(providerId: providerId, conversationId: conversationId)
            case .todoRead:
                guard shouldAcceptTodoRead(conversationId: conversationId) else { break }
                enableTaskPanelIfNeeded()
                break
            case .planStepUpdate(let stepId, let status, let stepTitle):
                let targetId = resolvePlanStepTargetConversationId(
                    eventConversationId: conversationId,
                    activeBuildPlanConversationId: activeBuildPlanConversationId,
                    activeTaskConversationId: chatStore.activeTaskConversationId
                )
                chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: targetId)
                if let sourcePlanId = activeBuildPlanConversationId, sourcePlanId != targetId {
                    chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: sourcePlanId)
                }
                // Cross-sync: PlanStep status → canonical TodoItem
                if let title = stepTitle {
                    let todoStatus: TodoStatus = {
                        switch status {
                        case .pending: return .pending
                        case .running: return .inProgress
                        case .done: return .done
                        case .failed: return .blocked
                        }
                    }()
                    let stepActiveForm: String? = status == .running ? title : nil
                    let updated = todoStore.upsertCanonicalOnlyFromAgent(
                        id: nil,
                        title: title,
                        status: todoStatus,
                        priority: nil,
                        notes: nil,
                        activeForm: stepActiveForm,
                        linkedFiles: []
                    )
                    if !updated,
                       !isPlanBuildContext(
                        conversationId: conversationId,
                        phase: planFlowPhase,
                        activeBuildPlanConversationId: activeBuildPlanConversationId,
                        activeBuildAgentConversationId: activeBuildAgentConversationId
                       ) {
                        todoStore.upsertFromAgent(
                            id: nil,
                            title: title,
                            status: todoStatus,
                            priority: nil,
                            notes: nil,
                            activeForm: stepActiveForm,
                            linkedFiles: []
                        )
                    }
                }
            case .debugPhaseUpdate(let phase, let detail):
                routeDebugEvent(
                    .debugPhaseUpdate(phase: phase, detail: detail),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugUserRequest(let kind, let prompt):
                routeDebugEvent(
                    .debugUserRequest(kind: kind, prompt: prompt),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugResolved(let summary):
                routeDebugEvent(
                    .debugResolved(summary: summary),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugLog(let payload):
                routeDebugEvent(
                    .debugLog(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugHypothesize(let payload):
                routeDebugEvent(
                    .debugHypothesize(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugMark(let payload):
                routeDebugEvent(
                    .debugMark(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugInstrument(let payload):
                routeDebugEvent(
                    .debugInstrument(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugClean(let payload):
                routeDebugEvent(
                    .debugClean(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugSession(let payload):
                routeDebugEvent(
                    .debugSession(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugQuery(let payload):
                routeDebugEvent(
                    .debugQuery(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .activatePlanMode(let reason):
                handleAutoActivatePlanMode(reason: reason)
            case .activateDebugMode(let reason):
                handleAutoActivateDebugMode(reason: reason)
            case .mermaidRender(let code, let title):
                let titlePrefix = title.map { "**\($0)**\n\n" } ?? ""
                let mermaidMarkdown = "\(titlePrefix)```mermaid\n\(code)\n```"
                if shouldRoutePlanStream(to: conversationId) {
                    appendPlanStreamingContent(
                        mermaidMarkdown,
                        conversationId: conversationId
                    )
                    if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
                } else {
                    // Non-plan flows keep the diagram in chat.
                    chatStore.updateLastAssistantMessage(
                        content: mermaidMarkdown,
                        in: conversationId,
                        persistImmediately: true
                    )
                }
            }
        }
    }

    private func recordExplicitTodoWrite(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        didReceiveExplicitTodoByMessage.insert(messageId)
        if let autoTodoId = autoTodoIdByMessage[messageId] {
            todoStore.remove(id: autoTodoId)
            autoTodoIdByMessage.removeValue(forKey: messageId)
            autoTodoCompletedOperationsByMessage.removeValue(forKey: messageId)
        }
    }

    private func ensureAutoTodoStartedBeforeOperationalActivity(
        activity _: TaskActivity,
        providerId _: String,
        conversationId _: UUID?
    ) {
        // Disabled: auto-TODO created placeholder items with generic titles
        // before the LLM had analyzed the task. Only explicit todo_write
        // events from the LLM should create TODOs.
    }

    private func updateAutoTodoProgressAfterOperationalActivity(
        activity _: TaskActivity,
        providerId _: String,
        conversationId _: UUID?
    ) {
        // Disabled: auto-TODO progress updates are no longer needed
        // since auto-TODO creation is disabled.
    }

    private func emitAutoTodoTraceUpdate(
        todoId: UUID,
        title: String,
        status: TodoStatus,
        notes: String,
        linkedFiles: [String],
        providerId: String,
        conversationId: UUID?,
        timestamp: Date
    ) {
        var payload: [String: String] = [
            "id": todoId.uuidString,
            "title": title,
            "task": title,
            "status": status.rawValue,
            "priority": TodoPriority.medium.rawValue,
            "notes": notes,
        ]
        if !linkedFiles.isEmpty {
            payload["files"] = linkedFiles.joined(separator: ",")
        }

        let activity = TaskActivity(
            type: "todo_write",
            title: "Todo updated",
            detail: title,
            payload: payload,
            timestamp: timestamp,
            phase: .planning,
            isRunning: false
        )
        enqueueTaskActivity(activity)
        appendToolTraceEvent(
            activity: activity,
            rawKind: .todoUpdate,
            providerId: providerId,
            conversationId: conversationId
        )
    }

    private func autoTodoTitle(for activity: TaskActivity) -> String {
        let normalizedTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty, !isPlaceholderTodoTitle(normalizedTitle) {
            return normalizedTitle
        }
        if let path = activity.payload["path"] ?? activity.payload["file"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let base = (path as NSString).lastPathComponent
            return "Complete changes on \(base)"
        }
        if let query = activity.payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Complete analysis: \(String(query.prefix(80)))"
        }
        if let command = activity.payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Complete execution: \(String(command.prefix(80)))"
        }
        return "Complete the required operational steps"
    }

    private func autoTodoLinkedFiles(from payload: [String: String]) -> [String] {
        var files = Set<String>()
        for candidate in [payload["path"], payload["file"], payload["files"]] {
            let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { continue }
            let splitItems = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if splitItems.isEmpty {
                files.insert(raw)
            } else {
                splitItems.forEach { files.insert($0) }
            }
        }
        return files.sorted()
    }

    private func shouldAcceptTodoWrite(_ todo: TodoWritePayload, conversationId: UUID?) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return true
        }
        if isPlaceholderTodoTitle(todo.title) {
            return false
        }
        // Always accept updates when agent todos already exist (status changes, new items).
        let hasExistingAgentTodo = todoStore.todos.contains {
            $0.source == .agent && !$0.isPlanCanonical
        }
        if hasExistingAgentTodo {
            return true
        }
        // Accept the first TodoWrite in a turn even without prior operational activity.
        // The mandatory workflow is: investigate → report → create TODO → resolve.
        // The agent may create TODOs before or after operational activity; both are valid.
        if hasOperationalActivityInCurrentTurn(conversationId: conversationId) {
            return true
        }
        // Accept the first explicit todo for this assistant message, even without
        // operational activity. This ensures the TODO live activity appears when
        // the agent creates tasks after analysis (including subagent/swarm analysis).
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            // When conversationId or assistantMessageId is unavailable (e.g. during
            // swarm follow-up), accept the todo so the live activity is not silently lost.
            return true
        }
        return !didReceiveExplicitTodoByMessage.contains(assistantMessageId)
    }

    private func shouldAcceptTodoRead(conversationId: UUID?) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return true
        }
        guard todoStore.todos.contains(where: { $0.source == .agent || $0.isPlanCanonical }) else {
            return false
        }
        return hasOperationalActivityInCurrentTurn(conversationId: conversationId)
    }

    private func hasOperationalActivityInCurrentTurn(conversationId: UUID?) -> Bool {
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            return false
        }
        if let cached = toolTraceOperationalSeenByMessage[assistantMessageId] {
            return cached
        }
        let existing = toolTraceStore.events(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )
        let hasOperational = existing.contains { isOperationalTraceEvent($0) }
        toolTraceOperationalSeenByMessage[assistantMessageId] = hasOperational
        return hasOperational
    }

    private func currentAssistantMessageIdForTrace(conversationId: UUID) -> UUID? {
        if let active = activeToolTraceTurnsByConversation[conversationId] {
            return active.assistantMessageId
        }
        return chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id
    }

    private func isOperationalTraceActivity(_ activity: TaskActivity) -> Bool {
        guard ToolTraceVisibility.shouldDisplay(activity: activity) else { return false }
        let type = activity.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded: Set<String> = [
            "todo_read",
            "todo_write",
            "plan_step",
            "plan_step_update",
            "activate_plan_mode",
            "activate_debug_mode",
            "policy_ack",
        ]
        return !excluded.contains(type)
    }

    private func isOperationalTraceEvent(_ event: ToolTraceEvent) -> Bool {
        guard ToolTraceVisibility.shouldDisplay(event: event) else { return false }
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded: Set<String> = [
            "todo_read",
            "todo_write",
            "plan_step",
            "plan_step_update",
            "activate_plan_mode",
            "activate_debug_mode",
            "policy_ack",
        ]
        return !excluded.contains(type)
    }

    private func isPlaceholderTodoTitle(_ rawTitle: String) -> Bool {
        let normalized = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        let genericTitles: Set<String> = [
            "task",
            "tasks",
            "todo",
            "todos",
            "step",
            "steps",
            "analysis",
            "workflow",
            "execution",
            "plan",
        ]
        if genericTitles.contains(normalized) {
            return true
        }
        if normalized.range(of: #"^(task|step)\s*\d*$"#, options: .regularExpression) != nil {
            return true
        }
        if normalized.contains("task panel")
            || normalized.contains("todo update")
            || normalized.contains("turn started")
        {
            return true
        }
        return false
    }

    @MainActor
    private func handleDebugPhaseUpdate(phase: DebugFlowPhase, detail: String?) {
        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }
        let previousPhase = debugStore.phase
        debugStore.setPhase(phase)
        let shouldClearQuestions = phase == .fixing
            || phase == .instrumenting
            || phase == .verifying
            || phase == .resolved
        if shouldClearQuestions, previousPhase != phase, !debugStore.clarificationQuestions.isEmpty {
            debugStore.clarificationQuestions = ""
        }
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debugStore.addLog(
                severity: .info,
                source: "debug_set_phase",
                message: "Phase → \(phase.label)",
                detail: detail,
                category: "system"
            )
        }
    }

    @MainActor
    private func handleDebugUserRequest(kind: String, prompt: String) {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { return }

        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }

        switch normalizedKind {
        case "reproduce":
            if debugStore.phase == .idle || debugStore.phase == .describing {
                debugStore.setPhase(.reproducing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        default:
            if debugStore.phase == .idle {
                debugStore.setPhase(.describing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        }
    }

    @MainActor
    private func handleDebugResolved(summary: String) {
        if debugStore.awaitingDebugClean {
            debugStore.addLog(
                severity: .warning,
                source: "debug_resolve",
                message: "Ignoring debug_resolve while waiting for debug_clean",
                category: "system"
            )
            return
        }
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        debugStore.resolveSession(
            summary: normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
        )
    }

    @MainActor
    private func handleDebugLogPayload(_ payload: DebugLogToolPayload) {
        debugStore.addLog(
            severity: payload.severity,
            source: payload.source,
            message: payload.message,
            detail: payload.detail,
            category: payload.category
        )

        let isRuntimeLike = payload.category == "runtime"
            || payload.category == "instrumentation"
            || !payload.data.isEmpty
            || !(payload.hypothesisId ?? "").isEmpty
        if isRuntimeLike {
            debugStore.addRuntimeLog(
                location: payload.source,
                message: payload.message,
                data: payload.data,
                hypothesisId: payload.hypothesisId,
                runId: payload.runId
            )
        }
    }

    @MainActor
    private func handleDebugHypothesizePayload(_ payload: DebugHypothesizeToolPayload) {
        switch payload.action {
        case "update":
            guard let hypothesisId = payload.hypothesisId,
                  let status = payload.status
            else {
                return
            }
            let updated = debugStore.updateHypothesis(id: hypothesisId, status: status, evidence: payload.evidence)
            if !updated {
                debugStore.addLog(
                    severity: .warning,
                    source: "debug_hypothesize",
                    message: "Hypothesis update ignored: unknown id",
                    detail: payload.hypothesisIdRaw,
                    category: "debug"
                )
            }
        default:
            let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let description = payload.description ?? ""
            let _ = debugStore.addHypothesis(
                id: payload.hypothesisId,
                title: title,
                description: description,
                status: payload.status ?? .proposed,
                evidence: payload.evidence
            )
        }
    }

    @MainActor
    private func handleDebugMarkPayload(_ payload: DebugMarkToolPayload) {
        debugStore.addDebugMarker(DebugMarker(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            markerComment: payload.comment,
            originalContent: payload.originalContent
        ))
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    private func handleDebugInstrumentPayload(_ payload: DebugInstrumentToolPayload) {
        let instrumentationType: InstrumentationPoint.InstrumentationType
        switch payload.type {
        case "assert":
            instrumentationType = .assertion
        case "timing":
            instrumentationType = .timing
        case "variable":
            instrumentationType = .variable
        default:
            instrumentationType = .logging
        }
        let displayLabel = payload.label?.isEmpty == false
            ? (payload.label ?? "")
            : (payload.expression ?? "instrumentation")
        debugStore.addInstrumentation(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            type: instrumentationType,
            code: displayLabel,
            hypothesisId: payload.hypothesisId
        )
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    private func handleDebugCleanPayload(_ payload: DebugCleanToolPayload) {
        if payload.dryRun {
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_clean",
                    message: "Dry-run preview received (cleanup not applied)",
                    detail: detail,
                    category: "system"
                )
            }
            return
        }

        let normalizedStatus = (payload.status ?? "completed").lowercased()
        let cleanSucceeded = !(normalizedStatus == "failed" || normalizedStatus == "error")

        if debugStore.awaitingDebugClean {
            debugStore.applyDebugCleanResult(success: cleanSucceeded, detail: payload.detail)
            return
        }

        if cleanSucceeded {
            _ = debugStore.cleanAllDebugMarkers()
            _ = debugStore.cleanAllInstrumentation()
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(severity: .info, source: "debug_clean", message: detail, category: "system")
            }
        }
    }

    @MainActor
    private func handleDebugSessionPayload(_ payload: DebugSessionToolPayload) {
        switch payload.action {
        case "start":
            if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
                debugStore.startDebugSession(errorContext: payload.detail ?? "")
            }
        case "clear":
            debugStore.clearLogs()
            debugStore.clearRuntimeLogs()
        case "end", "stop":
            if debugStore.phase != .resolved {
                debugStore.setPhase(.verifying)
            }
        default:
            break
        }
    }

    @MainActor
    private func handleDebugQueryPayload(_ payload: DebugQueryToolPayload) {
        let detail = payload.detail ?? "Debug query \(payload.format)"
        debugStore.addLog(
            severity: .info,
            source: "debug_query",
            message: detail,
            detail: payload.output,
            category: "debug"
        )
    }

    // MARK: - LLM Auto-Activation Handlers

    @MainActor
    private func handleAutoActivatePlanMode(reason: String?) {
        // Skip if already in plan mode or a plan flow is actively running.
        guard coderMode != .plan else { return }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .building:
            return
        default:
            break
        }
        selectMode(.plan)
        planToggleEnabled = true
        if !showPlanPanel {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
    }

    @MainActor
    private func handleAutoActivateDebugMode(reason: String?) {
        let normalizedReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if coderMode != .debug {
            selectMode(.debug)
        }
        if !showDebugPanel {
            debugToggleEnabled = true
            showDebugPanel = true
        } else {
            debugToggleEnabled = true
        }

        if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
            debugStore.startDebugSession(errorContext: normalizedReason ?? "")
            return
        }

        guard let normalizedReason, !normalizedReason.isEmpty else { return }
        if debugStore.errorSummary.isEmpty {
            debugStore.errorSummary = normalizedReason
        }
    }

    @MainActor
    private func enqueueTaskActivity(_ activity: TaskActivity) {
        pendingTaskActivities.append(activity)
        logTaskBacklogIfNeeded(context: "enqueue_activity")

        let needsImmediateFlush = activity.type == "agent"
            || activity.isRunning
            || TaskActivityStore.isConcreteVisibleEventType(activity.type)
        if needsImmediateFlush {
            taskFlushTask?.cancel()
            taskFlushTask = nil
            flushPendingTaskActivities()

            // Fast-path: push the sidebar subtitle immediately so it
            // reflects the current tool without waiting for the
            // TaskActivityStore's internal 50ms coalescing buffer.
            if TaskActivityStore.isConcreteVisibleEvent(activity) {
                let label = Self.immediateSubtitleLabel(for: activity)
                if !label.isEmpty, let cid = conversationId {
                    chatStore.setTaskStatus(label, for: cid)
                }
            }
        } else {
            scheduleTaskActivityFlush()
        }
    }

    private static func immediateSubtitleLabel(for activity: TaskActivity) -> String {
        let t = activity.type.lowercased()
        if activity.isRunning {
            if t.contains("read") || t.contains("glob") { return "Reading files" }
            if t.contains("grep") || t.contains("search") { return "Searching codebase" }
            if t.contains("edit") || t.contains("write") || t.contains("file_change") { return "Editing code" }
            if t.contains("bash") || t.contains("command") { return "Running command" }
            if t.contains("mcp") { return "Calling MCP tool" }
            if t.contains("web_search") { return "Searching web" }
            if t.contains("web_fetch") { return "Fetching page" }
            if t.contains("agent") || t.contains("subagent") { return "Running subagent" }
            if t.hasPrefix("debug_") { return "Debugging" }
            if t.contains("todo") || t.contains("plan_step") { return "Planning next move" }
            return "Running"
        }
        return ""
    }

    @MainActor
    private func scheduleTaskActivityFlush() {
        if taskFlushTask != nil { return }
        taskFlushTask = Task {
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                taskFlushTask = nil
                flushPendingTaskActivities()
            }
        }
    }

    @MainActor
    private func flushPendingTaskActivities() {
        let backlogBefore = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities = pendingTaskActivities
        let greps = pendingInstantGreps
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)

        for activity in activities {
            if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                || activity.type == "web_search_started"
                || activity.type == "web_search_completed"
                || activity.type == "web_search_failed"
                || activity.type == "web_fetch_started"
                || activity.type == "web_fetch_completed"
                || activity.type == "web_fetch_failed"
                || activity.type == "command_execution"
                || activity.type == "bash" || activity.type == "mcp_tool_call"
                || activity.type == "skill_invocation"
            {
                if taskActivityStore.shouldPreserveSwarmCriticalEvent(activity) {
                    taskActivityStore.addActivity(activity)
                } else {
                    taskActivityStore.appendOrMergeBatchEvent(activity)
                }
            } else {
                taskActivityStore.addActivity(activity)
            }
        }

        for grep in greps {
            taskActivityStore.addInstantGrep(grep)
        }

        updateSidebarTaskStatus()

        let backlogAfter = pendingTaskActivities.count + pendingInstantGreps.count
        if backlogAfter > 0 {
            logTaskBacklogIfNeeded(context: "flush_reschedule")
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    private func logTaskBacklogIfNeeded(context: String) {
        let backlog = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlog >= taskBacklogDiagnosticThreshold else { return }
        NSLog("[StreamDiag] task_backlog_high count=%d context=%@", backlog, context)
    }

    @MainActor
    private func clearTaskActivityPipeline() {
        taskFlushTask?.cancel()
        taskFlushTask = nil
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)
        taskActivityStore.clear()
    }

    private func activityWithConversationContext(
        _ activity: TaskActivity,
        conversationId: UUID?
    ) -> TaskActivity {
        guard let conversationId else { return activity }
        var payload = activity.payload
        if payload["conversation_id"] == nil {
            payload["conversation_id"] = conversationId.uuidString.lowercased()
        }
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }

    // MARK: - Composer
    @ViewBuilder
    private var composerArea: some View {
        VStack(spacing: 0) {
            ChatComposerView(
                inputText: $inputText,
                attachedAttachments: $attachedComposerAttachments,
                isSelectingImage: $isSelectingImage,
                isComposerDropTargeted: $isComposerDropTargeted,
                isConvertingHeic: $isConvertingHeic,
                isInputFocused: $isInputFocused,
                isProviderReady: isProviderReady,
                isLoading: isLoadingForCurrentConversation,
                planningState: planningState,
                runtimeRunState: executionController.runState,
                runtimeTaskStartDate: composerRuntimeStartDate,
                frozenTimerText: composerFrozenTimerText,
                frozenTimerDismissible: composerFrozenTimerDismissible,
                activeModeColor: activeModeColor,
                activeModeGradient: activeModeGradient,
                inputHint: inputHint,
                providerNotReadyMessage: providerNotReadyMessage,
                quickCommandPresets: composerQuickCommandPresets,
                showCodeReviewAutofixToggle: coderMode == .codeReviewMultiSwarm,
                showPlanRequestIndicator: showPlanRequestIndicator,
                controlsRow: AnyView(modeControlsRow),
                voiceState: voiceInputController.state,
                codeReviewAutofixEnabled: Binding(
                    get: { !codeReviewAnalysisOnly },
                    set: { enabled in
                        codeReviewAnalysisOnly = !enabled
                    }
                ),
                onSend: sendMessage,
                onApplyQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                },
                onInputTextChanged: { _ in },
                onRunQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                    sendMessage()
                },
                onPauseResume: { pauseOrResumeActiveTask() },
                onStop: {
                    lastTaskEndedByManualStop = true
                    interruptTask()
                },
                onDismissFrozenTimer: { composerFrozenTimerState = nil },
                onVoiceAction: { handleVoiceAction() },
                onOptimizePrompt: { optimizeCurrentPrompt() },
                isOptimizingPrompt: isOptimizingPrompt
            )
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .popover(isPresented: $showPromptOptimizerPopup, arrowEdge: .bottom) {
            PromptOptimizerPopup(
                originalPrompt: inputText,
                optimizedPrompt: optimizedPromptResult,
                onAccept: { accepted in
                    inputText = accepted
                    showPromptOptimizerPopup = false
                    isInputFocused = true
                },
                onCancel: {
                    showPromptOptimizerPopup = false
                }
            )
        }
        .alert("Rate Limit Reached", isPresented: $showRateLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rateLimitAlertText)
        }
    }

    @ViewBuilder
    private var modeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: $codexModelOverride,
            codexReasoningEffort: $codexReasoningEffort,
            codexSandbox: $codexSandbox,
            geminiModelOverride: $geminiModelOverride,
            swarmOrchestrator: $swarmOrchestrator,
            taskPanelEnabled: $taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $inputText,
            planModeBackend: $planModeBackend,
            swarmWorkerBackend: $swarmWorkerBackend,
            openaiModel: $openaiModel,
            claudeModel: $claudeModel,
            openrouterModel: $openrouterModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $planToggleEnabled,
            debugToggleEnabled: $debugToggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in
                    showSwarmPanel = newValue
                }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in
                    showCodeReviewPanel = newValue
                }
            ),
            browserToggleEnabled: Binding(
                get: { coderMode == .browser },
                set: { newValue in
                    if newValue {
                        selectMode(.browser)
                    } else if coderMode == .browser {
                        selectMode(.agent)
                    }
                }
            )
        )
    }

    @ViewBuilder
    private var usageFooterArea: some View {
        UsageFooterView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext,
            planModeBackend: planModeBackend,
            swarmWorkerBackend: swarmWorkerBackend,
            openaiModel: openaiModel,
            claudeModel: claudeModel,
            contextRefreshTick: streamContentVersion
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

    private var providerNotReadyMessage: String {
        guard let id = providerRegistry.selectedProviderId else {
            return "No provider selected. Go to Settings to configure."
        }
        switch id {
        case "openai-api": return "OpenAI API Key missing. Configure it in Settings."
        case "anthropic-api": return "Anthropic API Key missing. Configure it in Settings."
        case "google-api": return "Google Gemini API Key missing. Configure it in Settings."
        case "codex-cli":
            return "Codex CLI not connected. Configure it in Settings → Codex CLI."
        case "claude-cli":
            return "Claude Code not found. Configure it in Settings → Claude Code."
        case "gemini-cli":
            return "Gemini CLI not found/not authenticated. Configure it in Settings."
        case "openrouter-api": return "OpenRouter API Key missing. Configure it in Settings."
        case "minimax-api": return "MiniMax API Key missing. Configure it in Settings."
        default:
            return "Provider \"\(id)\" not authenticated. Go to Settings to configure."
        }
    }


    private var inputHint: String {
        switch coderMode {
        case .agent: return "Agent can modify files and run commands"
        case .codeReviewMultiSwarm:
            return
                "Code Review: analysis → dynamic worker tasks → parallel fix → test → re-review loop"
        case .debug: return "Debug mode: MCP-first phase flow + structured debug tools"
        case .plan: return "Plan with options + custom response"
        case .ide: return "IDE mode: API chat + manual editing in the editor"
        case .browser: return "Browser mode: agent can navigate, test, and capture screenshots"
        case .mcpServer: return "Send to configured MCP server"
        }
    }

    private var composerQuickCommandPresets: [ChatComposerView.QuickCommandPreset] {
        guard coderMode == .codeReviewMultiSwarm else { return [] }
        let defaults: [ChatComposerView.QuickCommandPreset] = [
            .init(
                id: "review-uncommitted",
                slash: "/review-uncommitted",
                label: "Full uncommitted audit",
                prompt:
                    """
                    Run ultra-deep code review on all uncommitted changes (staged, unstaged, untracked).
                    Required output:
                    1) prioritized findings (P0-P3),
                    2) impacted areas file-by-file,
                    3) regression risks,
                    4) final verdict on patch correctness.
                    """
            ),
            .init(
                id: "review-staged",
                slash: "/review-staged",
                label: "Staged diff only",
                prompt:
                    """
                    Review ONLY staged changes.
                    Ignore unstaged and untracked.
                    Return severe and actionable findings with priority/confidence.
                    """
            ),
            .init(
                id: "review-autofix",
                slash: "/review-autofix",
                label: "Review + auto fix",
                prompt:
                    """
                    Deep review uncommitted changes and directly fix all confirmed bugs.
                    After fixes, run relevant build/tests and report the technical changelog.
                    """
            ),
            .init(
                id: "review-autofix-commit",
                slash: "/review-autofix-commit",
                label: "Review + fix + commit",
                prompt:
                    """
                    Run full review on staged/unstaged/untracked, apply necessary fixes and create final atomic commit.
                    Requirements: no superfluous changes, green build/tests, specific commit message.
                    """
            ),
            .init(
                id: "review-focus-ui",
                slash: "/review-focus-ui",
                label: "Focus UI flows",
                prompt:
                    """
                    Focus on review realtime flows:
                    - visible step-by-step stream,
                    - live updated read/tool/terminal cards,
                    - consistent todos without layout glitches.
                    Fix any issues found and validate with tests/build.
                    """
            ),
        ]
        return defaults + customCodeReviewQuickPresets
    }

    private var customCodeReviewQuickPresets: [ChatComposerView.QuickCommandPreset] {
        struct CustomPreset: Decodable {
            let slash: String
            let label: String
            let prompt: String
        }
        let raw = codeReviewQuickCommandsCustomJSON.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            return []
        }
        return decoded.enumerated().compactMap { idx, item in
            let slash = item.slash.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard slash.hasPrefix("/"), !label.isEmpty, !prompt.isEmpty else { return nil }
            return .init(
                id: "review-custom-\(idx)-\(slash)",
                slash: slash,
                label: label,
                prompt: prompt
            )
        }
    }

    private var effectiveSandbox: String {
        codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
    }

    private func selectMode(_ mode: CoderMode) {
        userModeOverrideUntilConversationChange = true
        // One thread per context: conversation does not change on tab switch.
        // selectedConversationId stays, only coderMode and provider are updated.
        let currentConv = chatStore.conversation(for: selectedConversationId)
        switch mode {
        case .ide:
            if let preferred = currentConv?.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let id = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: currentConv?.preferredProviderId, registry: providerRegistry) {
                providerRegistry.selectedProviderId = id
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: current)
            {
                // Keep current provider if already valid for Agent
            } else {
                providerRegistry.selectedProviderId = providerRegistry.provider(for: "codex-cli") != nil ? "codex-cli" : nil
            }
        case .codeReviewMultiSwarm:
            if let id = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: currentConv?.preferredProviderId, registry: providerRegistry) {
                providerRegistry.selectedProviderId = id
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = providerRegistry.provider(for: "codex-cli") != nil ? "codex-cli" : nil
            }
        case .debug:
            if let id = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: currentConv?.preferredProviderId, registry: providerRegistry) {
                providerRegistry.selectedProviderId = id
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = providerRegistry.provider(for: "codex-cli") != nil ? "codex-cli" : nil
            }
            debugToggleEnabled = true
            showDebugPanel = true
        case .plan:
            if let id = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: currentConv?.preferredProviderId, registry: providerRegistry) {
                providerRegistry.selectedProviderId = id
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = providerRegistry.provider(for: "codex-cli") != nil ? "codex-cli" : nil
            }
            // Only reset plan state when no active flow is in progress
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building, .proposalReady, .readyToBuild:
                break
            default:
                planningState = .idle
                planFlowPhase = .idle
            }
            planToggleEnabled = true
        case .browser:
            if let id = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: currentConv?.preferredProviderId, registry: providerRegistry) {
                providerRegistry.selectedProviderId = id
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
            } else {
                providerRegistry.selectedProviderId = providerRegistry.provider(for: "codex-cli") != nil ? "codex-cli" : nil
            }
            showBrowserPanel = true
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        coderMode = mode
        // When switching away from plan mode, only preserve plan state for
        // actively in-flight phases (questioning/generating) so switching back
        // doesn't lose work. Reset all other phases to avoid orphaned state
        // since planToggleEnabled is disabled below.
        if mode != .plan {
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building:
                break
            case .idle:
                break
            case .proposalReady, .readyToBuild:
                planFlowPhase = .idle
                planningState = .idle
                clearPlanStreamingState()
            }
            planToggleEnabled = false
        }
        if mode != .debug && !debugStore.phase.isActive {
            debugToggleEnabled = false
            showDebugPanel = false
        }
        if mode != .browser {
            showBrowserPanel = false
        }
        chatStore.updateConversationMode(conversationId: selectedConversationId, mode: mode)
    }

    private func modeColor(for m: CoderMode) -> Color {
        switch m {
        case .agent: return DesignSystem.Colors.agentColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .debug: return DesignSystem.Colors.debugColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .browser: return DesignSystem.Colors.browserColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }
    private func modeIcon(for m: CoderMode) -> String {
        switch m {
        case .agent: return "brain"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .debug: return "ladybug.fill"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .browser: return "globe"
        case .mcpServer: return "server.rack"
        }
    }
    private func modeGradient(for m: CoderMode) -> LinearGradient {
        switch m {
        case .agent: return DesignSystem.Colors.agentGradient
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewGradient
        case .debug: return DesignSystem.Colors.debugGradient
        case .plan: return DesignSystem.Colors.planGradient
        case .ide: return DesignSystem.Colors.ideGradient
        case .browser: return DesignSystem.Colors.browserGradient
        case .mcpServer: return DesignSystem.Colors.mcpGradient
        }
    }

    // MARK: - Provider Sync

    private func checkProviderAuth() {
        if coderMode == .ide {
            let preferred = ProviderSupport.preferredIDEProvider(in: providerRegistry)
            if providerRegistry.selectedProviderId != preferred {
                DispatchQueue.main.async {
                    // Avoid re-entrant mutations during SwiftUI/AppKit transactions (Picker/Menu).
                    if coderMode == .ide, providerRegistry.selectedProviderId != preferred {
                        providerRegistry.selectedProviderId = preferred
                    }
                }
            }
        }
        let selectedProviderId = providerRegistry.selectedProviderId
        if multiCLIAccountEnabled,
            let selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            Task { @MainActor in
                let hasAvailable =
                    cliAccountRouter.currentAvailability(provider: kind) == .available
                isProviderReady = hasAvailable
                isAnyAgentProviderReady =
                    cliAccountRouter.currentAvailability(provider: .codex) == .available
                    || cliAccountRouter.currentAvailability(provider: .claude) == .available
                    || cliAccountRouter.currentAvailability(provider: .gemini) == .available
            }
            return
        }
        checkProviderAuthGeneration += 1
        let generation = checkProviderAuthGeneration
        let provider = providerRegistry.selectedProvider
        let codexProvider = providerRegistry.provider(for: "codex-cli")
        let claudeProvider = providerRegistry.provider(for: "claude-cli")
        let geminiProvider = providerRegistry.provider(for: "gemini-cli")
        let anyRealProvider = providerRegistry.providers.first {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id) && $0.isAuthenticated()
        }
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            let anyAgentReady =
                (codexProvider?.isAuthenticated() ?? false)
                || (claudeProvider?.isAuthenticated() ?? false)
                || (geminiProvider?.isAuthenticated() ?? false)
                || (anyRealProvider != nil)
            await MainActor.run {
                guard generation == checkProviderAuthGeneration else { return }
                isProviderReady = ready
                isAnyAgentProviderReady = anyAgentReady
            }
        }
    }

    private func syncCodexProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.codexProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func syncClaudeProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.claudeProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
    }

    private func syncGeminiProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.geminiProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: p)
        checkProviderAuth()
    }

    private func syncOpenRouterProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.openRouterAPIProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
    }

    @MainActor
    private func scheduleToolRuntimePolicySync(immediate: Bool = false) {
        if immediate {
            toolRuntimeSyncTask?.cancel()
            toolRuntimeSyncTask = nil
            syncToolRuntimePolicy()
            return
        }

        toolRuntimeSyncTask?.cancel()
        toolRuntimeSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000) // 180ms debounce
            guard !Task.isCancelled else { return }
            syncToolRuntimePolicy()
            toolRuntimeSyncTask = nil
        }
    }

    private func syncToolRuntimePolicy() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let codex = ProviderFactory.codexProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: codex)
        let claude = ProviderFactory.claudeProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: claude)
        let gemini = ProviderFactory.geminiProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: gemini)

        if !cfg.openrouterApiKey.isEmpty {
            let p = ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        }
        if !cfg.openaiApiKey.isEmpty {
            let p = ProviderFactory.openAIAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "openai-api", provider: p)
        }
        if !cfg.anthropicApiKey.isEmpty {
            let p = ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "anthropic-api", provider: p)
        }
        if !cfg.googleApiKey.isEmpty {
            let p = ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "google-api", provider: p)
        }
        if !cfg.minimaxApiKey.isEmpty {
            let p = ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "minimax-api", provider: p)
        }
        if !cfg.grokApiKey.isEmpty {
            let p = ProviderFactory.grokAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "grok-api", provider: p)
        }

        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
        injectBrowserBridgeIntoProviders()
    }

    private func injectBrowserBridgeIntoProviders() {
        for provider in providerRegistry.providers {
            if let toolProvider = provider as? ToolEnabledLLMProvider {
                Task {
                    await toolProvider.setBrowserBridge(browserTabManager)
                }
            }
        }
    }

    private func reregisterProviderPreservingSelection(id: String, provider: any LLMProvider) {
        let wasSelected = providerRegistry.selectedProviderId == id
        providerRegistry.unregister(id: id)
        providerRegistry.register(provider)
        if wasSelected {
            providerRegistry.selectedProviderId = id
        }
    }

    private func persistCodexConfigToToml() {
        var cfg = CodexConfigLoader.load()
        cfg.sandboxMode = codexSandbox.isEmpty ? nil : codexSandbox
        cfg.model = codexModelOverride.isEmpty ? nil : codexModelOverride
        cfg.modelReasoningEffort = codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        CodexConfigLoader.save(cfg)
    }
    private func syncSwarmProvider() {
        // Swarm provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }

    private var runtimeWorkspacePaths: [URL] {
        let contextPaths = effectiveContext.folderPaths
            .map { URL(fileURLWithPath: $0) }
        if !contextPaths.isEmpty {
            return contextPaths
        }
        return workspaceStore.activeWorkspacePaths
    }

    private func migrateSwarmProviderDefaultsIfNeeded() {
        guard !swarmProviderAutoMigrated else { return }
        if swarmOrchestrator == "openai" && swarmWorkerBackend == "codex" {
            swarmOrchestrator = "auto"
            swarmWorkerBackend = "auto"
        }
        swarmProviderAutoMigrated = true
    }
    private func syncCodeReviewRuntimeConfig() {
        // Review provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }
    private func syncProviderFromConversation() {
        guard let conv = chatStore.conversation(for: selectedConversationId), let mode = conv.mode
        else {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            return
        }
        coderMode = mode
        switch mode {
        case .ide:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: current)
            {
                // Keep current provider if already valid for Agent
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .codeReviewMultiSwarm, .plan:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            debugToggleEnabled = false
        case .debug:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            debugToggleEnabled = true
            showDebugPanel = true
        case .browser:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            showBrowserPanel = true
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        checkProviderAuth()
    }

    private func syncCoderModeToProvider(_ pid: String?) {
        if userModeOverrideUntilConversationChange {
            return
        }
        guard let id = pid else {
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        if ProviderSupport.isAgentCompatibleProvider(id: id) {
            if showDebugPanel || debugStore.phase.isActive {
                coderMode = .debug
            } else {
                coderMode = .agent
            }
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        if ProviderSupport.isIDEProvider(id: id) {
            coderMode = .ide
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        switch id {
        case "codex-cli", "claude-cli", "gemini-cli":
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
        default: break
        }
    }
    private func syncPlanProvider() {
        // Plan mode uses selected real provider at runtime.
        checkProviderAuth()
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        let parsedClaudeTools = ProviderFactory.normalizedToolList(from: claudeAllowedTools)
        return ProviderFactoryConfig(
            openaiApiKey: openaiApiKey,
            openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            grokApiKey: "",
            grokModel: "",
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
            planModeBackend: planModeBackend,
            swarmOrchestrator: swarmOrchestrator,
            swarmWorkerBackend: swarmWorkerBackend,
            swarmEnabledRoles: swarmEnabledRoles,
            globalYolo: globalYolo,
            codeReviewPartitions: codeReviewPartitions,
            codeReviewAnalysisOnly: codeReviewAnalysisOnly,
            codeReviewMaxRounds: codeReviewMaxRounds,
            codeReviewAnalysisBackend: codeReviewAnalysisBackend,
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: parsedClaudeTools,
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride,
            unifiedToolRuntimeEnabled: unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: agentsHardBlockEnabled,
            mcpEditEnforcementEnabled: mcpEditEnforcementEnabled,
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }

    private func trySummarizeIfNeeded(ctx: WorkspaceContext) async {
        guard let conv = chatStore.conversation(for: conversationId) else { return }
        guard conv.messages.count >= (summarizeKeepLast + 4) else { return }

        let activeModel = resolveActiveModelForContext()
        let size = resolvedContextWindowSizeForSummarize(model: activeModel)
        let ctxPrompt = ctx.contextPrompt()
        let (_, _, pct) = ContextEstimator.estimate(
            messages: conv.messages, contextPrompt: ctxPrompt, modelContextSize: size,
            lastInputTokens: conv.lastInputTokens)
        guard pct >= summarizeThreshold else { return }

        if let prov = providerRegistry.provider(for: summarizeProvider), prov.isAuthenticated() {
            await runSummarize(provider: prov, ctx: ctx)
        } else if let fallback = providerRegistry.selectedProvider, fallback.isAuthenticated() {
            await runSummarize(provider: fallback, ctx: ctx)
        } else {
            for pid in ["claude-cli", "codex-cli", "gemini-cli", "anthropic-api", "openai-api", "google-api"] {
                if let p = providerRegistry.provider(for: pid), p.isAuthenticated() {
                    await runSummarize(provider: p, ctx: ctx)
                    return
                }
            }
        }
    }

    private func resolveActiveModelForContext() -> String {
        let pid = providerRegistry.selectedProviderId ?? ""
        switch pid {
        case "codex-cli": return codexModelOverride.isEmpty ? "gpt-5-codex" : codexModelOverride
        case "claude-cli": return claudeModel
        case "gemini-cli": return geminiModelOverride.isEmpty ? googleModel : geminiModelOverride
        case "openai-api": return openaiModel
        case "anthropic-api": return anthropicModel
        case "google-api": return googleModel
        default: return openaiModel
        }
    }

    private func resolvedContextWindowSizeForSummarize(model: String) -> Int {
        let normalized = model.lowercased()
        if normalized.contains("gemini") { return 1_048_576 }
        if normalized.contains("gpt-5") || normalized.contains("codex") { return 200_000 }
        if normalized.contains("claude") { return 200_000 }
        return ContextEstimator.contextSize(for: providerRegistry.selectedProviderId, model: model)
    }

    private func runSummarize(provider: any LLMProvider, ctx: WorkspaceContext) async {
        await MainActor.run { isSummarizing = true }
        defer { Task { @MainActor in isSummarizing = false } }
        do {
            _ = try await chatStore.summarizeConversation(
                id: conversationId, keepLast: summarizeKeepLast, provider: provider, context: ctx)
        } catch {
            // Do not block on error
        }
    }

    // MARK: - Delegate to Agent (from IDE)
    private func delegateToAgent() {
        var msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            msg =
                chatStore.conversation(for: conversationId)?.messages.last(where: {
                    $0.role == .user
                })?.content ?? ""
        }
        guard !msg.isEmpty || !attachedComposerAttachments.isEmpty else { return }
        let codex = providerRegistry.provider(for: "codex-cli")
        let claude = providerRegistry.provider(for: "claude-cli")
        let agentProvider: (any LLMProvider)? =
            codex?.isAuthenticated() == true
            ? codex : (claude?.isAuthenticated() == true ? claude : nil)
        guard let agentProvider else { return }

        let currentConv = chatStore.conversation(for: conversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath
        let agentConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: .agent)

        selectedConversationId = agentConvId
        providerRegistry.selectedProviderId = agentProvider.id
        coderMode = .agent
        inputText = msg.isEmpty ? "" : msg

        sendMessage()
    }

    // MARK: - Plan Choice Execution
    private func preferredRealProvider() -> (any LLMProvider)? {
        if let selectedId = providerRegistry.selectedProviderId,
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: selectedId, registry: providerRegistry),
           let selected = providerRegistry.provider(for: selectedId),
           selected.isAuthenticated() {
            return selected
        }
        if let fallback = providerRegistry.providers.first(where: {
            ProviderSupport.isPlanBuildExecutionCapableProvider(id: $0.id, registry: providerRegistry)
                && $0.isAuthenticated()
        }) {
            return fallback
        }
        return nil
    }

    private func resolvePreferredRealProvider() -> (any LLMProvider)? {
        if let provider = preferredRealProvider() {
            return provider
        }
        appendTechnicalErrorMessage(
            "[Provider] No authenticated execution-capable provider available.",
            in: conversationId
        )
        return nil
    }

    @MainActor
    private func submitPlanClarificationAnswers(_ submission: PlanClarificationSubmission) {
        let orderedAnswers = submission.answers.sorted(by: { $0.questionId < $1.questionId })
        guard !orderedAnswers.isEmpty else { return }
        let finalNote = submission.finalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswers = orderedAnswers.map { answer in
            let normalizedCustom = answer.customResponse?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PlanClarificationAnswer(
                questionId: answer.questionId,
                question: answer.question,
                optionId: answer.optionId,
                optionText: answer.optionText,
                optionIds: answer.optionIds,
                optionTexts: answer.optionTexts,
                customResponse: (normalizedCustom?.isEmpty == false) ? normalizedCustom : nil
            )
        }
        let prompt = buildPlanClarificationPrompt(
            PlanClarificationSubmission(
                answers: normalizedAnswers,
                finalNote: finalNote
            )
        )

        // Store answers and continue the flow. Phase is set to .analyzing because the
        // post-clarification flow starts with a re-analysis pass before plan generation.
        planClarificationAnswers = String(prompt.prefix(16_000))
        planningState = .idle
        clearPlanStreamingState()
        planFlowPhase = .analyzing

        // Safety net: ensure any lingering task from the questioning phase is ended
        // before we attempt to continue. This prevents the guard in continuePlanFlowPhase3
        // from silently blocking the flow after event refactoring.
        if let convId = conversationId, chatStore.isTaskActive(for: convId) {
            NSLog("[PlanFlow] submitPlanClarificationAnswers: forcing endTask for lingering task on %@", convId.uuidString)
            snapshotSubagentCardsAndEndTask(conversationId: convId)
        }

        if coderMode == .agent {
            planToggleEnabled = true
        }
        recordTaskActivity(
            type: "plan_answers_submitted",
            payload: [
                "title": "Plan answers submitted",
                "detail": "Clarification answers were confirmed in the Plan Panel.",
                "status": "completed",
            ],
            providerId: providerRegistry.selectedProviderId ?? "plan-ui",
            conversationId: conversationId
        )

        continuePlanFlowPhase3()
    }

    @MainActor
    private func selectPlanChoice(
        _ choice: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil,
        providerOverrideId: String? = nil
    ) {
        let normalized = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard planFlowPhase != .building else { return }
        let planConversationId = explicitPlanConversationId ?? conversationId
        chatStore.choosePlanPath(normalized, for: planConversationId)
        if let selected = planHistoryStore.selectedEntryId {
            planHistoryStore.updateChosenPath(id: selected, chosenPath: normalized)
        }
        if planFlowPhase == .proposalReady || planFlowPhase == .idle {
            planFlowPhase = .readyToBuild
        }
        // Do NOT auto-execute: wait for user to click "Build" in the plan panel.
    }

    @MainActor
    private func handleCustomPlanResponseSelection(
        _ response: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil
    ) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let hasTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(trimmed)
        let todos = PlanOptionsParser.extractTodosFromOptionText(trimmed)
        if hasTodoHeader, !todos.isEmpty {
            executeWithPlanChoice(
                trimmed,
                fromPlanConversationId: explicitPlanConversationId
            )
            return
        }

        // A free-form custom response should regenerate a plan, not try to execute
        // immediately (execution requires a compliant `## Todo` checklist).
        let baseRequest = planUserRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedRequest: String
        if baseRequest.isEmpty {
            mergedRequest = trimmed
        } else {
            mergedRequest = """
            \(baseRequest)

            Custom direction:
            \(trimmed)
            """
        }
        inputText = "/plan \(mergedRequest)"
        isInputFocused = true
        sendMessage()
    }

    private func executeWithPlanChoice(
        _ choice: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil,
        providerOverrideId: String? = nil,
        allowIdleRebuild: Bool = false
    ) {
        guard conversationId != nil else { return }
        let planConversationId = explicitPlanConversationId ?? conversationId
        let hasActiveBuildTask = activeBuildAgentConversationId.map { chatStore.isTaskActive(for: $0) } ?? false
        let canStartBuild = shouldAllowStartingPlanBuild(
            isLoadingCurrentConversation: isLoadingForCurrentConversation,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            hasActiveBuildTask: hasActiveBuildTask
        )
        guard canStartBuild else {
            if hasActiveBuildTask {
                let scopeText =
                    (activeBuildPlanConversationId == planConversationId)
                    ? ""
                    : " for another conversation"
                appendTechnicalErrorMessage(
                    "[Plan] A build is already running\(scopeText). Wait for completion before starting another build.",
                    in: conversationId
                )
            }
            return
        }
        if activeBuildPlanConversationId != nil, !hasActiveBuildTask {
            // Defensive cleanup for stale build IDs after interruptions.
            activeBuildPlanConversationId = nil
            activeBuildAgentConversationId = nil
        }
        guard canExecutePlanBuild(
            phase: planFlowPhase,
            choice: choice,
            allowIdleRebuild: allowIdleRebuild
        ) else {
            appendTechnicalErrorMessage(
                "[Plan] Build not available. Generate a valid plan first.",
                in: conversationId
            )
            return
        }
        let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
        let planTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard hasRequiredTodoHeader, !planTodos.isEmpty else {
            appendTechnicalErrorMessage(
                "[Plan] Build requires a todo checklist in the selected option.",
                in: conversationId
            )
            if !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: true,
                    source: .manualDeepLink
                )
            }
            return
        }
        let provider: any LLMProvider
        let normalizedOverride = providerOverrideId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overrideId = normalizedOverride, !overrideId.isEmpty {
            guard isPlanExecutionProviderIdAllowed(overrideId) else {
                appendTechnicalErrorMessage(
                    "[Plan] Invalid provider (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            guard isPlanBuildExecutionCapableProvider(overrideId, registry: providerRegistry) else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not execution-capable (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            if let overrideProvider = providerRegistry.provider(for: overrideId) {
                if overrideProvider.isAuthenticated() {
                    provider = overrideProvider
                } else {
                    appendTechnicalErrorMessage(
                        "[Plan] Provider not authenticated (\(overrideProvider.displayName)). Using fallback.",
                        in: conversationId
                    )
                    guard let backendProvider = resolvePreferredRealProvider() else {
                        return
                    }
                    provider = backendProvider
                }
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not available (\(overrideId)). Using fallback.",
                    in: conversationId
                )
                guard let backendProvider = resolvePreferredRealProvider() else {
                    return
                }
                provider = backendProvider
            }
        } else {
            guard let backendProvider = resolvePreferredRealProvider() else {
                return
            }
            provider = backendProvider
        }

        let currentConv = chatStore.conversation(for: conversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath
        let agentConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: .agent)
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        do {
            try createCheckpointBeforeTurn(conversationId: agentConvId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: agentConvId)
            return
        }

        planningState = .idle
        planFlowPhase = .readyToBuild
        chatStore.choosePlanPath(choice, for: planConversationId)

        todoStore.upsertCanonicalPlanTodos(planTodos)
        let canonicalTodos = todoStore.todos.filter { $0.isPlanCanonical }
        chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planConversationId)

        if let selected = planHistoryStore.selectedEntryId {
            planHistoryStore.updateChosenPath(id: selected, chosenPath: choice)
            planHistoryStore.markRebuilt(id: selected)
        }
        // Keep the user on the plan conversation — build progress is visible
        // in the plan panel's trace section. Only switch mode and phase.
        providerRegistry.selectedProviderId = provider.id
        coderMode = .agent
        planFlowPhase = .building
        activeBuildPlanConversationId = planConversationId
        activeBuildAgentConversationId = agentConvId

        let planBuildAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: planBuildAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: agentConvId
        )
        suppressedEmptyBuildAssistantMessageIds.insert(planBuildAssistantMessageId)
        startToolTraceTurn(
            conversationId: agentConvId,
            assistantMessageId: planBuildAssistantMessageId,
            providerId: provider.id
        )
        chatStore.beginTask(conversationId: agentConvId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: agentConvId
        ) {
            clearTaskActivityPipeline()
        }
        scheduleFallbackTurnStartEvent(conversationId: agentConvId, providerId: provider.id)

        let planExecutionWorkflow = """
            **FUNDAMENTAL RULE: The plan TODOs are your BIBLE. Follow them EXACTLY in the order listed.**

            **Todo Workflow (strict, no noise):**
            1. The canonical plan TODOs are IMMUTABLE: do NOT create new TODOs, do NOT modify titles, do NOT reorder. Execute EXACTLY those present in the given order.
            2. For each TODO: set status=in_progress BEFORE starting, then status=done AFTER completion. Use \(CoderIDEMarkers.todoWritePrefix) to update the status.
            3. Emit \(CoderIDEMarkers.showTaskPanel) only if useful to visualize a real multi-step execution. Never emit it as a placeholder.
            4. Do NOT skip any TODO. Do NOT proceed to the next TODO until the current one is done.
            5. If a TODO is blocked, explain why and try to resolve it before moving on.
            6. Before finishing: ALL canonical TODOs MUST be done. If any is not done, do NOT terminate.
            7. Do not repeat the plan in chat: execute, update status, provide minimal operational feedback.
            8. Do NOT post kickoff fillers like "starting build/execution": begin directly from concrete execution updates.
            """

        let executionPlanBase: String
        if let board = chatStore.planBoard(for: planConversationId), !board.goal.isEmpty {
            executionPlanBase = """
            **Objective:** \(board.goal)

            **Plan (selected option):**
            \(choice)
            """
        } else {
            executionPlanBase = "**Plan to implement:**\n\(choice)"
        }

        let prompt = buildPlanExecutionPrompt(
            workflowInstructions: planExecutionWorkflow,
            executionPlanBase: executionPlanBase,
            planTodos: planTodos,
            canonicalTodos: canonicalTodos
        ).prompt

        launchRunTask(for: agentConvId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    attachments: nil,
                    onText: { content in
                        applyStreamingUpdate(content: content, conversationId: agentConvId)
                    },
                    onRaw: { t, p, pid in
                        handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: agentConvId)
                    },
                    onError: { content in
                        Task { @MainActor in
                            chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
                        }
                    },
                    onSignal: nil
                )
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                await MainActor.run {
                    if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                        planFlowPhase = .readyToBuild
                    } else if planFlowPhase == .building {
                        planFlowPhase = .idle
                    }
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: agentConvId) { $0.interrupt() }
                        if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                            planFlowPhase = .readyToBuild
                        } else if planFlowPhase == .building {
                            planFlowPhase = .idle
                        }
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: agentConvId)
                    await MainActor.run {
                        applyFlowCoordinatorState(for: agentConvId) { $0.fail() }
                        if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                            planFlowPhase = .readyToBuild
                        } else if planFlowPhase == .building {
                            planFlowPhase = .idle
                        }
                    }
                }
            }
            finalizeToolTraceTurn(conversationId: agentConvId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(conversationId: agentConvId)
            await MainActor.run {
                chatStore.removeAssistantMessageIfEmpty(
                    messageId: planBuildAssistantMessageId,
                    in: agentConvId
                )
                suppressedEmptyBuildAssistantMessageIds.remove(planBuildAssistantMessageId)
                if traceOutcome == .success, let planConvId = activeBuildPlanConversationId {
                    let canonicalTodos = todoStore.todos.filter(\.isPlanCanonical)
                    let agentMessages = chatStore.conversation(for: agentConvId)?
                        .messages.filter { $0.role == .assistant } ?? []
                    let traceEventsForWalkthrough = toolTraceStore.allEvents(conversationId: agentConvId)
                    let walkthroughMd = buildWalkthroughMarkdown(
                        canonicalTodos: canonicalTodos,
                        planBoard: chatStore.planBoard(for: planConvId),
                        agentMessages: agentMessages,
                        traceEvents: traceEventsForWalkthrough
                    )
                    chatStore.setWalkthrough(walkthroughMd, for: planConvId)

                    let doneCount = canonicalTodos.filter { $0.status == .done }.count
                    let totalCount = canonicalTodos.count
                    let goalText = chatStore.planBoard(for: planConvId)?.goal ?? "Plan"
                    let recap = doneCount == totalCount
                        ? "Build complete. All \(totalCount) steps done: \(goalText)"
                        : "Build finished. \(doneCount)/\(totalCount) steps completed: \(goalText)"
                    chatStore.addMessage(
                        ChatMessage(id: UUID(), role: .assistant, content: recap),
                        to: agentConvId
                    )

                    // Add a Code Review & Test todo after plan build completion
                    todoStore.upsertFromAgent(
                        id: nil,
                        title: "Code Review & Test",
                        status: .pending,
                        priority: .high,
                        notes: "Review changes and run tests",
                        activeForm: "Reviewing code and running tests",
                        linkedFiles: []
                    )
                }
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
            }
        }
    }

    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    private func quotedReplyText(for message: ChatMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .components(separatedBy: .newlines)
            .map { line in
                let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? ">" : "> \(normalized)"
            }
            .joined(separator: "\n")
    }

    private func beginReply(to message: ChatMessage) {
        let quoted = quotedReplyText(for: message)
        inputText = quoted.isEmpty ? "" : "\(quoted)\n\n"
        isInputFocused = true
    }

    private func mapAttachmentKindToLLM(_ kind: ChatAttachmentKind) -> LLMAttachmentKind {
        switch kind {
        case .image: return .image
        case .document: return .document
        case .file: return .file
        }
    }

    private func prepareRuntimeAttachmentURL(
        sourceURL: URL,
        workspaceURL: URL,
        turnId: UUID
    ) -> URL {
        let standardizedSource = sourceURL.standardizedFileURL
        let standardizedWorkspace = workspaceURL.standardizedFileURL
        if standardizedSource.path.hasPrefix(standardizedWorkspace.path) {
            return standardizedSource
        }

        let runtimeDir = standardizedWorkspace
            .appendingPathComponent(".codigo_attachments", isDirectory: true)
            .appendingPathComponent(turnId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let ext = standardizedSource.pathExtension
        let baseName = standardizedSource.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .prefix(40)
        let runtimeFileName = ext.isEmpty
            ? "\(UUID().uuidString)_\(baseName)"
            : "\(UUID().uuidString)_\(baseName).\(ext)"
        let runtimeURL = runtimeDir.appendingPathComponent(String(runtimeFileName))
        if !FileManager.default.fileExists(atPath: runtimeURL.path) {
            try? FileManager.default.copyItem(at: standardizedSource, to: runtimeURL)
        }
        return runtimeURL
    }

    private func buildAttachmentBundle(
        attachments: [ComposerAttachment],
        workspaceURL: URL,
        turnId: UUID,
        capabilities: ProviderAttachmentCapabilities
    ) -> (chat: [ChatAttachment], llm: [LLMAttachment], fallbackPreamble: String) {
        guard !attachments.isEmpty else { return ([], [], "") }

        var chatAttachments: [ChatAttachment] = []
        var llmAttachments: [LLMAttachment] = []
        var fallbackLines: [String] = []

        for item in attachments {
            let runtimeURL = prepareRuntimeAttachmentURL(
                sourceURL: item.url,
                workspaceURL: workspaceURL,
                turnId: turnId
            )
            let chatAttachment = ChatAttachment(
                kind: item.kind,
                originalName: item.originalName,
                mimeType: item.mimeType,
                localPath: item.url.path,
                sizeBytes: item.sizeBytes
            )
            chatAttachments.append(chatAttachment)
            llmAttachments.append(
                LLMAttachment(
                    kind: mapAttachmentKindToLLM(item.kind),
                    url: runtimeURL,
                    mimeType: item.mimeType,
                    filename: item.originalName,
                    sizeBytes: item.sizeBytes
                )
            )

            let isNativeSupported: Bool
            switch item.kind {
            case .image:
                isNativeSupported = capabilities.nativeImage
            case .document:
                isNativeSupported = capabilities.nativeDocument
            case .file:
                isNativeSupported = capabilities.nativeFile
            }
            if !isNativeSupported {
                let sizeText = item.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "n/a"
                fallbackLines.append("- \(item.originalName) [\(item.kind.rawValue)] path=\(runtimeURL.path) size=\(sizeText)")
            }
        }

        let preamble: String
        if fallbackLines.isEmpty {
            preamble = ""
        } else {
            preamble = """
            ## Attachments available for this request
            The following files are NOT natively supported by the provider and are available via local path:
            \(fallbackLines.joined(separator: "\n"))

            Use file reading tools to analyze them if needed.
            """
        }

        return (chatAttachments, llmAttachments, preamble)
    }

    // MARK: - Prompt Optimization

    private func optimizeCurrentPrompt() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let selectedProvider = providerRegistry.selectedProvider else { return }

        // Use lightweight provider (no tools/policy) when available — much faster for prompt optimization.
        // Fall back to full runtime provider if lightweight is not configured or not authenticated.
        let providerToUse: any LLMProvider
        if let providerId = providerRegistry.selectedProviderId,
           let lightweight = ProviderFactory.lightweightProvider(
               providerId: providerId,
               config: providerFactoryConfig(),
               executionController: executionController
           ),
           lightweight.isAuthenticated() {
            providerToUse = lightweight
        } else if let resolved = resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: false,
            forcePlanInline: false
        ) {
            providerToUse = resolved
        } else {
            providerToUse = selectedProvider
        }

        isOptimizingPrompt = true
        promptOptimizerTask?.cancel()
        promptOptimizerTask = Task {
            defer { isOptimizingPrompt = false }
            do {
                let ctx = WorkspaceContext.minimal()
                let optimized = try await PromptOptimizerService.optimize(
                    prompt: prompt,
                    using: providerToUse,
                    context: ctx
                )
                guard !Task.isCancelled else { return }
                optimizedPromptResult = optimized
                showPromptOptimizerPopup = true
            } catch {
                guard !Task.isCancelled else { return }
                appendTechnicalErrorMessage("[Prompt Optimizer] \(error.localizedDescription)", in: conversationId)
            }
        }
    }

    private func sendMessage() {
        let parsedInput = parsePlanCommandInput(inputText)
        let text = parsedInput.llmPromptInput
        let displayedInput = parsedInput.displayedInput
        let forcePlanInline = parsedInput.forcePlanInline
        if forcePlanInline {
            // `/plan` should force the planning flow and open the dedicated panel.
            planToggleEnabled = true
            if !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        }
        guard !text.isEmpty || !attachedComposerAttachments.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Error] No conversation selected. Create or select a thread and try again.",
                in: nil
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Error] No provider selected. Configure a provider in Settings.",
                in: targetConversationId
            )
            return
        }
        hasJustCompletedTask = false

        // Check rate limit before proceeding — show alert popup if at 100%
        if let rateLimitMsg = providerUsageStore.rateLimitAlertMessage(
            for: providerRegistry.selectedProviderId)
        {
            rateLimitAlertText = rateLimitMsg
            showRateLimitAlert = true
            return
        }

        // Opening the plan panel should not automatically activate planning.
        let shouldRunPlanInline = resolveShouldRunPlanInline(
            forcePlanInline: forcePlanInline,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        )
        let isPlanModeRequested = (coderMode == .plan || shouldRunPlanInline)
        func resetPlanFlowAfterPreflightFailureIfNeeded() {
            guard shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: isPlanModeRequested,
                phase: planFlowPhase
            ) else {
                return
            }
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }
        if isPlanModeRequested {
            // Guard against launching a new plan flow while one is already in progress
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building:
                appendTechnicalErrorMessage(
                    "[Plan] A plan flow is already in progress. Please wait for it to finish or interrupt it first.",
                    in: targetConversationId
                )
                return
            default:
                break
            }
            planFlowPhase = .analyzing
            planningState = .idle
            planAnalysisContext = ""
            planUserRequest = String(text.prefix(16_000))
            planClarificationAnswers = ""
            planClarificationCycles = 0
            clearPlanStreamingState()
            planShouldRunInline = shouldRunPlanInline
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        } else if planFlowPhase != .building {
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }

        // 1. Resolve the runtime provider
        guard
            let runtimeProvider = resolveRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline
            )
        else {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Error] Unable to resolve runtime provider for this mode.",
                in: targetConversationId
            )
            return
        }

        let selectedProviderAuthenticated = runtimeProvider.isAuthenticated()
        let preferredFallbackProvider = preferredRealProvider()
        var effectiveRuntimeProvider: any LLMProvider = runtimeProvider
        if shouldFallbackToPreferredProvider(
            selectedProviderIsAuthenticated: selectedProviderAuthenticated,
            hasPreferredAuthenticatedFallback: preferredFallbackProvider != nil
        ),
            let fallbackProvider = preferredFallbackProvider
        {
            effectiveRuntimeProvider = fallbackProvider
            appendTechnicalErrorMessage(
                "[Provider] \(runtimeProvider.displayName) not authenticated. Using fallback: \(fallbackProvider.displayName).",
                in: targetConversationId
            )
        } else if !selectedProviderAuthenticated {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Error] Provider \(providerName) not authenticated and no fallback available. Open Settings and authenticate an execution-capable provider.",
                in: targetConversationId
            )
            return
        }

        // 2. Build workspace context & checkpoint
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // 3. Prepare messages in chat store
        let turnId = UUID()
        let attachmentBundle = buildAttachmentBundle(
            attachments: attachedComposerAttachments,
            workspaceURL: ctx.workspacePath,
            turnId: turnId,
            capabilities: effectiveRuntimeProvider.attachmentCapabilities
        )
        let imagePathsToStore = attachmentBundle.chat
            .filter { $0.kind == .image }
            .map(\.localPath)
        inputText = ""
        let userVisibleText = displayedInput
        let contentToStore =
            userVisibleText.isEmpty ? (attachmentBundle.chat.isEmpty ? "" : "[Attached files]") : userVisibleText
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore,
                attachments: attachmentBundle.chat.isEmpty ? nil : attachmentBundle.chat
            ),
            to: targetConversationId
        )
        let standardAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: standardAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: targetConversationId
        )
        startToolTraceTurn(
            conversationId: targetConversationId,
            assistantMessageId: standardAssistantMessageId,
            providerId: effectiveRuntimeProvider.id
        )
        if let conv = chatStore.conversation(for: targetConversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId, folderPath: conv.contextFolderPath, conversationId: conv.id)
        }
        chatStore.beginTask(conversationId: targetConversationId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: targetConversationId
        ) {
            clearTaskActivityPipeline()
        }
        // Preserve manual todos across turns; for a new standard turn reset all agent todos,
        // including stale canonical plan tasks from previous plans/conversations.
        // During an active plan build, keep canonical todos so the build's todo
        // tracking isn't wiped by a concurrent user message.
        let hasActivePlanBuildTask = activeBuildAgentConversationId.map { chatStore.isTaskActive(for: $0) } ?? false
        let shouldClearPlanCanonicalTodos = shouldClearPlanCanonicalTodosOnNewTurn(
            phase: planFlowPhase,
            hasActivePlanBuildTask: hasActivePlanBuildTask
        )
        todoStore.clearAgentTodos(includePlanCanonical: shouldClearPlanCanonicalTodos)
        scheduleFallbackTurnStartEvent(
            conversationId: targetConversationId,
            providerId: effectiveRuntimeProvider.id
        )
        swarmProgressStore.clear()

        let attachmentsToSend = attachmentBundle.llm.isEmpty ? nil : attachmentBundle.llm
        attachedComposerAttachments = []

        // 4. Build the prompt with mode-specific instructions
        let basePrompt = buildPrompt(userText: text, shouldRunPlanInline: shouldRunPlanInline)
        let prompt = attachmentBundle.fallbackPreamble.isEmpty
            ? basePrompt
            : "\(attachmentBundle.fallbackPreamble)\n\n\(basePrompt)"

        // 5. Execute async stream
        let isPlanMultiTurnFlow = (coderMode == .plan || shouldRunPlanInline) && planFlowPhase == .analyzing
        launchRunTask(for: targetConversationId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                if isPlanMultiTurnFlow {
                    // Multi-turn forced sequential plan flow
                    try await runMultiTurnPlanFlow(
                        provider: effectiveRuntimeProvider,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        conversationId: targetConversationId,
                        shouldRunPlanInline: shouldRunPlanInline
                    )
                    // Safety net: if the flow returned without advancing to a terminal
                    // state (e.g., early return from a conversation-ID guard), reset the
                    // phase so the user isn't permanently stuck.
                    // Exception: .questioning + .awaitingClarification is a legitimate
                    // pause — the user needs to answer before the flow continues.
                    await MainActor.run {
                        guard shouldMutatePlanState(
                            targetConversationId: targetConversationId,
                            currentConversationId: self.conversationId
                        ) else { return }
                        let isPausedForClarification: Bool = {
                            if case .awaitingClarification = planningState { return true }
                            return false
                        }()
                        switch planFlowPhase {
                        case .analyzing, .generating:
                            NSLog("[PlanFlow] Safety reset: planFlowPhase was still %@ after runMultiTurnPlanFlow returned", String(describing: planFlowPhase))
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        case .questioning where !isPausedForClarification:
                            NSLog("[PlanFlow] Safety reset: planFlowPhase was .questioning without awaitingClarification")
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        default:
                            break
                        }
                    }
                } else {
                    // Standard single-stream flow (non-plan modes + plan build)
                    let streamResult = try await flowCoordinator.runStream(
                        provider: effectiveRuntimeProvider,
                        prompt: prompt,
                        context: ctx,
                        attachments: attachmentsToSend,
                        onText: { content in
                            applyStreamingUpdate(
                                content: content,
                                conversationId: targetConversationId
                            )
                        },
                        onRaw: { t, p, pid in
                            handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: targetConversationId)
                        },
                        onError: { content in
                            Task { @MainActor in
                                chatStore.updateLastAssistantMessage(content: content, in: targetConversationId)
                            }
                        },
                        onSignal: nil
                    )

                    let finalizedResult = try await continueIfPrematureStub(
                        initial: streamResult,
                        provider: effectiveRuntimeProvider,
                        originalPrompt: prompt,
                        context: ctx,
                        conversationId: targetConversationId,
                        hideContentDuringPlanDiscovery: false
                    )

                    // 6. Handle stream completion (plan options)
                    await handleStreamResult(
                        conversationId: targetConversationId,
                        fullText: finalizedResult, shouldRunPlanInline: shouldRunPlanInline,
                        ctx: ctx, attachmentsToSend: attachmentsToSend, prompt: prompt
                    )
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId)
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.fail() }
                    }
                }
                // C1 fix: Reset plan flow phase on error to prevent permanent stuck state.
                // Also reset if conversation changed but phase is stuck in a progress state.
                await MainActor.run {
                    guard shouldMutatePlanState(
                        targetConversationId: targetConversationId,
                        currentConversationId: self.conversationId
                    ) else { return }
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        }
    }

    // MARK: - Multi-Turn Plan Flow

    private func runMultiTurnPlanFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 1: Codebase Analysis
        // ========================
        let shouldStartPhase1 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .analyzing
            clearPlanStreamingState()
            return true
        }
        guard shouldStartPhase1 else {
            // Conversation changed before Phase 1 could start.
            return
        }

        let analysisPrompt = buildPhase1AnalysisPrompt(userRequest: planUserRequest)
        let analysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: analysisPrompt,
            context: ctx,
            attachments: attachmentsToSend,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                Task { @MainActor in
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let analysisText = analysisResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRequestClarifications = shouldAskPlanClarifications(
            analysisText: analysisText,
            userRequest: planUserRequest
        )

        await MainActor.run {
            guard self.conversationId == conversationId else { return }
            planAnalysisContext = analysisText
            updatePlanStreamingContent(analysisText, conversationId: conversationId)
            chatStore.updateLastAssistantMessage(
                content: analysisText,
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            let transitionMessage = shouldRequestClarifications
                ? "Analysis complete. Checking if clarifications are needed..."
                : "Analysis complete. Generating definitive plan in the Plan Panel..."
            chatStore.addMessage(
                ChatMessage(id: UUID(), role: .assistant, content: transitionMessage),
                to: conversationId
            )
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        }

        if !shouldRequestClarifications {
            // Skip the question phase for well-scoped requests and continue directly.
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                planningState = .idle
                clearPlanStreamingState()
            }
            try await runPlanFlowPhase3(
                provider: provider,
                ctx: ctx,
                conversationId: conversationId,
                shouldRunPlanInline: shouldRunPlanInline
            )
            return
        }

        // ========================
        // PHASE 2: Clarification Questions
        // ========================
        let shouldStartPhase2 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            clearPlanStreamingState()
            planFlowPhase = .questioning
            let questionAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: questionAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            chatStore.updateLastAssistantMessage(
                content: "Generating clarification questions...",
                in: conversationId,
                persistImmediately: true
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: questionAssistantMessageId,
                providerId: provider.id
            )
            return true
        }
        guard shouldStartPhase2 else {
            // Conversation changed before Phase 2.
            return
        }

        let questionPrompt = buildPhase2QuestionPrompt(
            userRequest: planUserRequest,
            analysisContext: analysisResult
        )
        let questionResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: questionPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                Task { @MainActor in
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let questionText = questionResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let questionDecision = decidePlanQuestionPhaseOutput(
            questionText,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        if case .clarification(let questions) = questionDecision {
            // Parse questions and pause for user input
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                planClarificationCycles += 1
                planningState = .awaitingClarification(questions: questions)
                updatePlanStreamingContent(questionText, conversationId: conversationId)
                chatStore.updateLastAssistantMessage(
                    content: "Questions ready — answer in the plan panel.",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
            // STOP — Phase 3 will be triggered by submitPlanClarificationAnswers() → continuePlanFlowPhase3()
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            return
        }

        // No structured clarification questions — proceed directly to Phase 3.
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
        let phase2Summary = hasNoQuestionsNeededSignal(questionText)
            ? "No questions needed. Generating plan..."
            : "Question phase completed. Generating plan..."
        await MainActor.run {
            guard shouldMutatePlanState(
                targetConversationId: conversationId,
                currentConversationId: self.conversationId
            ) else { return }
            planningState = .idle
            chatStore.addMessage(
                ChatMessage(id: UUID(), role: .assistant, content: phase2Summary),
                to: conversationId
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearPlanStreamingState()
        }
        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

    private func runPlanFlowPhase3(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 3: Plan Generation
        // ========================
        let shouldStartPhase3 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .generating
            let generationAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: generationAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: generationAssistantMessageId,
                providerId: provider.id
            )
            chatStore.updateLastAssistantMessage(
                content: "Generating definitive plan...",
                in: conversationId,
                persistImmediately: true
            )
            return true
        }
        guard shouldStartPhase3 else {
            // Conversation changed before Phase 3.
            return
        }

        let generationPrompt = buildPhase3GenerationPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let generationResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: generationPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                Task { @MainActor in
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        func parsePlanOptions(_ text: String) -> [PlanOption] {
            let strict = PlanOptionsParser.parseStrict(from: text)
            if !strict.isEmpty { return strict }
            return PlanOptionsParser.parse(from: text)
        }

        func areAllOptionsTodoCompliant(_ options: [PlanOption]) -> Bool {
            guard !options.isEmpty else { return false }
            let compliant = PlanOptionsParser.todoCompliantOptions(from: options)
            return compliant.count == options.count
        }

        var full = generationResult
        var options = parsePlanOptions(full)

        // Hard enforcement: every option must contain an explicit `## Todo` section.
        let maxRepairAttempts = 2
        var repairAttempt = 0
        while !areAllOptionsTodoCompliant(options), repairAttempt < maxRepairAttempts {
            repairAttempt += 1

            await MainActor.run {
                clearPlanStreamingState()
                chatStore.updateLastAssistantMessage(
                    content: "Regenerating plan... (attempt \(repairAttempt)/\(maxRepairAttempts))",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(true, in: conversationId)
            }

            let repairPrompt = buildPhase3TodoComplianceRepairPrompt(
                userRequest: planUserRequest,
                analysisContext: planAnalysisContext,
                clarificationAnswers: planClarificationAnswers,
                invalidPlanOutput: full
            )

            let repairedResult = try await flowCoordinator.runStream(
                provider: provider,
                prompt: repairPrompt,
                context: ctx,
                attachments: nil,
                onText: { [self] content in
                    updatePlanStreamingContent(content, conversationId: conversationId)
                },
                onRaw: { [self] t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { [self] content in
                    Task { @MainActor in
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    }
                },
                onSignal: nil
            )

            full = repairedResult
            options = parsePlanOptions(full)
        }

        await MainActor.run {
            guard shouldMutatePlanState(
                targetConversationId: conversationId,
                currentConversationId: self.conversationId
            ) else { return }
            updatePlanStreamingContent(full, conversationId: conversationId)
        }
        chatStore.setLastAssistantStreaming(false, in: conversationId)
        clearStreamingReasoning(for: conversationId)
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)

        if !options.isEmpty, areAllOptionsTodoCompliant(options) {
            let compliantOptions = PlanOptionsParser.todoCompliantOptions(from: options)
            let board = PlanBoard.build(from: full, options: compliantOptions)
            chatStore.setPlanBoard(board, for: conversationId)
            let currentConv = chatStore.conversation(for: conversationId)
            let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
            chatStore.updateLastAssistantMessage(
                content: "Plan ready in Plan Panel: \(parsedSummary.title)",
                in: conversationId,
                persistImmediately: true
            )

            _ = planHistoryStore.createEntry(
                conversationId: conversationId,
                contextId: currentConv?.contextId,
                contextFolderPath: currentConv?.contextFolderPath,
                title: parsedSummary.title,
                markdown: full,
                options: compliantOptions,
                chosenPath: board.chosenPath,
                tags: [],
                sourceMessageId: nil
            )

            inlinePlanSummaries.removeValue(forKey: conversationId)

            if shouldRunPlanInline {
                let contextId = currentConv?.contextId
                let contextFolderPath = currentConv?.contextFolderPath
                let planConvId = chatStore.getOrCreateConversationForMode(
                    contextId: contextId, contextFolderPath: contextFolderPath,
                    mode: .plan)
                chatStore.setPlanBoard(board, for: planConvId)
            }

            await MainActor.run {
                guard self.conversationId == conversationId else {
                    return
                }
                planFlowPhase = .proposalReady
                planningState = .awaitingChoice(planContent: full, options: compliantOptions)
                if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        } else {
            chatStore.updateLastAssistantMessage(
                content: "Plan generation failed. Please try again.",
                in: conversationId,
                persistImmediately: true
            )
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                clearPlanStreamingState()
                planFlowPhase = .idle
                planningState = .idle
            }
        }
    }

    @MainActor
    private func continuePlanFlowPhase3() {
        guard let targetConversationId = conversationId else {
            NSLog("[PlanFlow] continuePlanFlowPhase3 aborted: conversationId is nil")
            return
        }
        // Don't silently block if a lingering task is still marked active — force-end it.
        // The user explicitly submitted clarification answers, so the flow must continue.
        if isLoadingForCurrentConversation {
            NSLog("[PlanFlow] continuePlanFlowPhase3: isLoading=true for %@, force-ending lingering task", targetConversationId.uuidString)
            snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        }

        let effectiveProvider: any LLMProvider
        if let selected = providerRegistry.selectedProvider {
            if selected.isAuthenticated() {
                effectiveProvider = selected
            } else if let fallback = preferredRealProvider() {
                effectiveProvider = fallback
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] No authenticated provider available.",
                    in: targetConversationId
                )
                return
            }
        } else {
            appendTechnicalErrorMessage(
                "[Plan] No provider selected.",
                in: targetConversationId
            )
            return
        }

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        // Create a checkpoint before the post-clarification flow so we can
        // rewind if the re-analysis or plan generation causes unwanted changes.
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // Recompute inline flag fresh instead of relying on the stale captured
        // planShouldRunInline — the user may have toggled modes since the original request.
        let currentShouldRunInline = resolveShouldRunPlanInline(
            forcePlanInline: false,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        ) || planShouldRunInline // preserve original intent as fallback

        chatStore.beginTask(conversationId: targetConversationId)
        launchRunTask(for: targetConversationId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                try await runPostClarificationFlow(
                    provider: effectiveProvider,
                    ctx: ctx,
                    conversationId: targetConversationId,
                    shouldRunPlanInline: currentShouldRunInline
                )
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId
                    )
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.fail() }
                    }
                }
                // C1 fix: Reset plan flow phase on error to prevent permanent stuck state.
                // Also reset if conversation changed but phase is stuck in a progress state.
                await MainActor.run {
                    guard shouldMutatePlanState(
                        targetConversationId: targetConversationId,
                        currentConversationId: self.conversationId
                    ) else { return }
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        }
    }

    /// After clarification answers, re-analyze and decide: ask more questions or proceed to plan generation.
    private func runPostClarificationFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        let shouldStartReanalysis = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .analyzing
            clearPlanStreamingState()
            let reanalysisAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: reanalysisAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: reanalysisAssistantMessageId,
                providerId: provider.id
            )
            return true
        }
        guard shouldStartReanalysis else {
            // Conversation changed before post-clarification reanalysis.
            return
        }

        let reAnalysisPrompt = buildPostClarificationAnalysisPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let reAnalysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: reAnalysisPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                Task { @MainActor in
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let reAnalysisText = reAnalysisResult.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the LLM produced more questions or is ready for plan generation
        let classification = PlanOutputClassifier.classify(
            fullText: reAnalysisText,
            current: .questioning,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        let allowFollowUpClarification = shouldAllowFollowUpClarification(
            userRequest: planUserRequest,
            clarificationCycles: planClarificationCycles
        )

        if allowFollowUpClarification,
           classification.isConfident,
           case .awaitingClarification(let q) = classification.planningState
        {
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                planClarificationCycles += 1
                let followUp = "\n\n--- Follow-up analysis ---\n\(reAnalysisText)"
                planAnalysisContext = String((planAnalysisContext + followUp).suffix(32_000))
                planFlowPhase = .questioning
                planningState = .awaitingClarification(questions: q)
                updatePlanStreamingContent(reAnalysisText, conversationId: conversationId)
                chatStore.updateLastAssistantMessage(
                    content: "Questions ready — answer in the plan panel.",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
            // STOP — will re-enter via submitPlanClarificationAnswers → continuePlanFlowPhase3
            return
        }

        let shouldProceedPhase3 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            let postClarification = "\n\n--- Post-clarification analysis ---\n\(reAnalysisText)"
            planAnalysisContext = String((planAnalysisContext + postClarification).suffix(32_000))
            chatStore.updateLastAssistantMessage(
                content: "Questions answered. Generating definitive plan...",
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearPlanStreamingState()
            return true
        }
        guard shouldProceedPhase3 else {
            // Conversation changed before Phase 3.
            return
        }

        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

    private func continueIfPrematureStub(
        initial: String,
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> String {
        var combinedText = initial
        let maxAutoContinuationRounds = 3
        var round = 0

        while shouldAutoContinueStub(combinedText),
              round < maxAutoContinuationRounds {
            round += 1
            let continuationPrompt = """
            Immediately continue your previous response and complete the task to a concrete outcome.
            Execute needed steps autonomously (analyze, act, verify, fix if needed) and do not stop at intentions.

            Original request:
            \(originalPrompt)

            Text already sent:
            \(combinedText)
            """

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
                        : combined
                    applyStreamingUpdate(
                        content: displayContent,
                        conversationId: conversationId
                    )
                },
                onRaw: { t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { content in
                    DispatchQueue.main.async {
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp
        }

        return combinedText
    }

    private func shouldAutoContinueStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let low = trimmed.lowercased()
        let stubSignals = [
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "first, i'll",
            "first i will",
            "let me start",
            "let me begin",
            "let me check",
            "i can continue",
            "would you like me to",
            "if you want i can",
            "next i'll",
            "next i will",
        ]
        if stubSignals.contains(where: { low.contains($0) }) {
            return true
        }
        if low.hasSuffix("...") || low.hasSuffix(":") {
            return true
        }
        return false
    }

    // MARK: - Resolve Runtime Provider

    private func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool
    ) -> (any LLMProvider)? {
        // Plan/Swarm use real selected providers, without virtual providers.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return selectedProvider
        }
        // Code Review Multi-Swarm: build dedicated multi-swarm provider
        if coderMode == .codeReviewMultiSwarm {
            let cfg = providerFactoryConfig()
            if let multiSwarm = ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths
            ) {
                return multiSwarm
            }
            // Factory returned nil — surface the error in chat so the user knows.
            // Common cause: API key missing for the selected backend.
            let analysisBackend = cfg.codeReviewAnalysisBackend
            let executionBackend = cfg.codeReviewExecutionBackend
            let msg = "[Code Review] Failed to create multi-swarm provider (analysis: \(analysisBackend), execution: \(executionBackend)). Check your API keys in Settings. Falling back to standard agent."
            print("[CodeReview] WARNING: \(msg)")
            appendTechnicalErrorMessage(msg, in: conversationId)
            return selectedProvider
        }
        if multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            // Check if all accounts are exhausted
            if case .allExhausted(let reason) = cliAccountRouter.currentAvailability(
                provider: kind)
            {
                appendTechnicalErrorMessage(
                    "[Multi-account \(kind.displayName): \(reason). Configure accounts or reset limits in Settings.]",
                    in: conversationId)
                return nil
            }
            let availability = cliAccountRouter.currentAvailability(provider: kind)
            if case .allExhausted = availability {
                return selectedProvider
            }
            return CLIMultiAccountProviderAdapter(
                providerKind: kind,
                id: selectedProviderId,
                displayName: selectedProvider.displayName,
                router: cliAccountRouter,
                accountsStore: cliAccountsStore,
                makeProvider: { _, env in
                    let cfg = providerFactoryConfig()
                    let subagentFactory = ProviderFactory.subagentProviderFactory(
                        config: cfg,
                        executionController: executionController,
                        codebaseIndex: workspaceStore.codebaseIndex,
                        workspacePaths: runtimeWorkspacePaths
                    )
                    switch kind {
                    case .codex:
                        return ProviderFactory.codexProvider(
                            config: cfg, executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .claude:
                        return ProviderFactory.claudeProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .gemini:
                        return ProviderFactory.geminiProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    }
                }
            )
        }
        return selectedProvider
    }

    // MARK: - Clarification Heuristics

    private func userExplicitlyWantsClarifications(_ userRequest: String) -> Bool {
        let normalized = userRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.range(
            of: #"(chiedi|fammi|poni).{0,20}(domande|chiarimenti)|ask.{0,20}(questions|clarifications)"#,
            options: .regularExpression
        ) != nil
    }

    private func shouldAskPlanClarifications(analysisText: String, userRequest: String) -> Bool {
        if userExplicitlyWantsClarifications(userRequest) {
            return true
        }

        let normalized = "\(analysisText)\n\(userRequest)".lowercased()
        let blockingPatterns: [String] = [
            #"\b(blocked|cannot proceed|can't proceed|impossible to proceed)\b"#,
            #"\b(missing requirement|missing decision|decision needed|unknown requirement)\b"#,
            #"\b(ambiguous|unclear|not enough information|insufficient information)\b"#,
            #"\b(conflicting requirement|conflicting constraints|trade[- ]off not specified)\b"#,
            #"\b(need clarification|requires clarification|clarification required)\b"#,
        ]
        var hits = 0
        for pattern in blockingPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                hits += 1
            }
        }
        return hits >= 3
    }

    private func shouldAllowFollowUpClarification(
        userRequest: String,
        clarificationCycles: Int
    ) -> Bool {
        // Keep a single clarification round by default to avoid loops.
        guard clarificationCycles < 1 else {
            return false
        }
        return userExplicitlyWantsClarifications(userRequest)
    }

    // MARK: - Build Prompt

    private func buildPrompt(userText: String, shouldRunPlanInline: Bool) -> String {
        var prompt =
            userText.isEmpty
            ? "[The user attached an image. Analyze it and respond.]" : userText

        // Plan mode: response to clarification questions → include context to proceed
        if shouldUseClarificationPrompt(
            coderMode: coderMode,
            planningState: planningState,
            shouldRunPlanInline: shouldRunPlanInline
        ),
            case .awaitingClarification(let questions) = planningState
        {
            prompt = """
            The user has answered your clarification questions.

            User's answers:
            \(userText.isEmpty ? "[No text provided]" : userText)

            The original questions were:
            \(questions)

            Next steps:
            1. Perform ADDITIONAL codebase analysis based on these answers (use Read, Glob, Grep).
            2. If you are blocked by a hard missing decision, output ONE additional ## Questions section (same A/B/C/D format).
            3. Otherwise proceed directly to generate ONE definitive plan with ## Plan: Title and ## Todo sections.
            CRITICAL: prefer proceeding to plan generation; follow-up questions are exceptional.
            """
        }

        if coderMode == .ide {
            prompt =
                "Reply with text only. Do not modify files or run commands.\n\n" + prompt
        }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + prompt }
        if coderMode == .debug || showDebugPanel {
            let debugModeContract = """
            [DEBUG MODE ACTIVE]
            Use MCP-first typed debug panel controls only:
            - `debug_set_phase` with phase in: describing, reproducing, fixing, instrumenting, verifying, resolved.
            - `debug_request_user` with kind question|reproduce and a concrete prompt.
            - `debug_resolve` with final summary.
            Legacy `debug_panel` is invalid and must not be used.
            Keep debug artifacts tracked through `debug_mark`, `debug_log`, `debug_query`, `debug_hypothesize`, `debug_clean`.
            """
            prompt = debugModeContract + "\n\n" + prompt
        }
        let isPlanningDiscoveryFlow =
            (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .building

        if isPlanningDiscoveryFlow {
            let planningInstructions = """
            **MANDATORY Planning Workflow — Follow these phases in EXACT order:**

            ## PHASE 1: CODEBASE ANALYSIS (ALWAYS REQUIRED)
            Before producing ANY output, you MUST:
            - Use Read, Glob, and Grep to explore at least 3-5 relevant files
            - Understand the project structure, dependencies, and constraints
            - DO NOT skip this phase. DO NOT produce questions or options without reading files first.

            ## PHASE 2: CLARIFICATION QUESTIONS (ONLY IF BLOCKED)
            After analysis, ask clarifications ONLY when there is a blocking ambiguity that prevents a concrete plan.
            - Output ONLY a section with this EXACT format:

            ## Questions
            1. Question text?
            A) Option A text
            B) Option B text
            C) Option C text (optional)
            D) Other (specify)

            Rules: 1-3 questions max, each with 2-4 options A) B) C) D), mutually exclusive.
            Include "Other (specify)" ONLY for genuinely open-ended questions.
            Mark the best option with "(Recommended)" suffix, e.g.: A) Use SwiftUI (Recommended)
            For questions where multiple answers can be selected, add "(select all that apply)" to the question.
            DO NOT output anything else besides the ## Questions section.
            NEVER include ## Plan or ## Todo in a response with ## Questions.
            If the request is implementable with reasonable assumptions, skip questions.

            ## PHASE 3: DEFINITIVE PLAN (ONLY after Phases 1+2 resolved)
            Generate ONE definitive implementation plan (the best approach):
            ## Plan: Title
            Description, rationale, trade-offs.
            ## Todo
            - [ ] Step 1
            - [ ] Step 2

            ## MERMAID DIAGRAMS (ALWAYS include when applicable)
            When analyzing problems or creating plans, ALWAYS include a mermaid diagram to visualize:
            - Architecture and component relationships
            - Data flows and event pipelines
            - Implementation step dependencies
            Use a ```mermaid code block in your response. The IDE will render it as an interactive diagram.

            CRITICAL: NEVER combine ## Questions and ## Plan in the same response.
            Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) during planning.
            """
            prompt = planningInstructions + "\n\n" + prompt
        } else if ProviderSupport.isAgentCompatibleProvider(id: providerRegistry.selectedProviderId) {
                let baseInstructions = """
                    **Todo Workflow (use only when truly needed):**
                    1. Start with analysis (read/search) first. Do NOT create todos before understanding the task.
                    2. If the task is simple (single action or <=2 concrete operations), do NOT emit todo markers.
                    3. If the task is genuinely multi-step, create ONE coherent todo list after analysis with only concrete, executable steps.
                    3b. For multi-step execution, emit the first \(CoderIDEMarkers.todoWritePrefix) update BEFORE the first command/edit/tool action.
                    4. Never create placeholder todos (forbidden examples: "Task", "Analysis", "Step 1", "Setup task panel", "Todo update").
                    5. Emit \(CoderIDEMarkers.showTaskPanel) only when a real todo list exists or when the user explicitly asks.
                    6. During execution, update status only for real todos: in_progress before work, done after completion.
                    7. Emit \(CoderIDEMarkers.todoRead) only for resume/reconciliation when needed, never as a default first action.
                    8. If MCP is available and external/domain capabilities are needed, verify MCP availability first with `mcp_list_servers`, then `mcp_list_tools`, and run calls with `mcp_call`.
                    9. When MCP is used, explicitly report which MCP servers and MCP tools were used.
                    10. If context contains a required marker `[CODERIDE:policy_ack|hash=...]`, emit it once before any operational tool action.
                    11. If subagent tools are available, the FIRST operational tool round must start with at least one `subagent_*` call. For independent workstreams, call 2-5 subagents in the same round.
                    12. For implementation tasks, always run `subagent_reviewer` + `subagent_testWriter` before finalizing.
                    13. When the first subagent starts, emit \(CoderIDEMarkers.showSwarmPanel) so the swarm panel/card lane is visible.
                    To update plan steps use marker:
                    \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
                    For code searches with rg, you can emit markers with results:
                    \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:line]
                    Read files in parallel batches (max 8 per batch) when broad context is needed. To track the batch you can emit:
                    \(CoderIDEMarkers.readBatchPrefix)count=8|files=FileA.swift,FileB.swift|group_id=batch-1]
                    For concurrent web searches (max 4 queries in parallel), emit status markers:
                    \(CoderIDEMarkers.webSearchPrefix)queryId=q1|query=swift concurrency|status=started|group_id=web-1]
                    """
                prompt = baseInstructions + "\n" + prompt
                if !todoStore.todos.isEmpty {
                    let todoSection = todoStore.todos.sorted { $0.status.rank < $1.status.rank }
                        .map { t -> String in
                            let check = t.status == .done ? "x" : " "
                            return "- [\(check)] \(t.title) (\(t.status.rawValue))"
                        }
                        .joined(separator: "\n")
                    prompt += "\n\n## Current todos\n\(todoSection)"
                }
            }

        let convoContext = recentConversationContextForPrompt()
        if !convoContext.isEmpty {
            prompt += "\n\n## Conversation context (recent)\n\(convoContext)\nUse this context to answer follow-ups consistently."
        }
        return prompt
    }

    private func recentConversationContextForPrompt(maxMessages: Int = 30, maxCharsPerMessage: Int = 2500) -> String {
        chatStore.buildPromptContext(
            conversationId: conversationId,
            maxMessages: maxMessages,
            maxCharsPerMessage: maxCharsPerMessage,
            includeMemorySummary: true
        )
    }

    // MARK: - Phase-Specific Plan Prompts

    private func buildPhase1AnalysisPrompt(userRequest: String) -> String {
        """
        **Phase: Codebase Analysis (ANALYSIS ONLY)**

        You are analyzing a codebase to prepare a plan. Your ONLY task is to explore and understand the codebase.

        User request: \(userRequest)

        Instructions:
        1. Use Read, Glob, and Grep to explore files relevant to this request.
        2. Identify key files, dependencies, current architecture, and constraints.
        3. Report your findings as structured analysis text.
        4. Do NOT propose solutions, options, or clarification questions.
            5. Do NOT generate ## Todo sections or ## Plan headers.
        6. Focus on WHAT EXISTS, not what should change.
        7. Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.
        8. Include a ```mermaid diagram showing the architecture, component relationships, or data flow relevant to this request.

        Output format: A structured analysis report of your findings.
        """
    }

    private func buildPostClarificationAnalysisPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        """
        **Phase: Post-clarification Analysis**

        The user answered your clarification questions. Based on the answers, perform ADDITIONAL codebase analysis.

        User request: \(userRequest)

        Previous codebase analysis:
        \(analysisContext)

        User clarification answers:
        \(clarificationAnswers)

        Instructions:
        1. Use Read, Glob, and Grep to explore specific files relevant based on the user's answers.
        2. Deep-dive into the areas indicated by the user's choices.
        3. Ask follow-up questions ONLY if there is a hard blocker. Otherwise continue without questions.
        4. If blocked, generate at most ONE additional question set using the format:

        ## Questions
        1. Question?
        A) Option A
        B) Option B
        C) Other (specify)

        5. If you have sufficient information, provide an analysis report without questions.
        6. Do NOT generate ## Plan, ## Todo or plan proposals in this phase.
        7. Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.
        """
    }

    private func buildPhase2QuestionPrompt(userRequest: String, analysisContext: String) -> String {
        """
        **Phase: Clarification Questions**

        Based on the codebase analysis below, determine if you need clarifications from the user.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)

        Instructions:
        - If you can proceed with reasonable assumptions, respond ONLY with: NO_QUESTIONS_NEEDED
        - Ask questions ONLY when blocked by missing requirements or conflicting constraints.
        - If blocked, generate 1-3 structured questions in this EXACT format:

        ## Questions
        1. Question text?
        A) First concrete option
        B) Second concrete option
        C) Third option (optional, only if useful)
        D) Other (specify)

        2. Second question?
        A) First option
        B) Second option

        STRICT rules for questions:
        - Minimum 1, maximum 3 questions
        - Each question MUST have 2-4 options labeled A) B) C) D)
        - Options must be mutually exclusive and concrete (not vague)
        - Include "D) Other (specify)" ONLY for genuinely open-ended questions
        - The header MUST be exactly "## Questions" (no localized alternatives)
        - Do NOT include ## Plan, ## Todo or plan proposals
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        - The format must be EXACTLY as above: number + text + options A) B) C) on separate lines
        """
    }

    private func buildPhase3GenerationPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        var prompt = """
        **Phase: Plan Generation**

        Generate ONE definitive implementation plan based on the analysis and context below.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Instructions:
        - Generate ONE definitive implementation plan using this EXACT format:

        ## Plan: Title
        Description of the approach, rationale, trade-offs, and key implementation notes.

        ## Todo
        - [ ] Step 1
        - [ ] Step 2
        - [ ] Step 3

        - Include a ```mermaid diagram showing the implementation plan dependencies and flow.

        Rules:
        - The plan MUST include the exact header `## Todo`.
        - Under `## Todo`, include 3-8 checklist items using `- [ ] ...`.
        - Do NOT use alternative headers like "Tasks", "Steps", or "Checklist".
        - Steps must be concrete and directly implementable.
        - Do NOT ask questions or request clarifications
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        """

        return prompt
    }

    private func buildPhase3TodoComplianceRepairPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String,
        invalidPlanOutput: String
    ) -> String {
        let clippedInvalidOutput = String(invalidPlanOutput.prefix(8_000))
        var prompt = """
        **Phase: Plan Format Repair**

        Your previous output is INVALID because the plan is missing the required `## Todo` section.
        Rewrite the plan from scratch.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Invalid previous output (for reference):
        \(clippedInvalidOutput)

        Hard constraints (MANDATORY):
        - Output ONE plan using a `## Plan: Title` header.
        - The plan MUST contain the exact header `## Todo`
        - Under `## Todo`, include 3-8 checklist items using `- [ ]`
        - Do NOT use alternative headers like Tasks/Steps/Checklist
        - Output only the final markdown plan (no commentary)
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        """

        return prompt
    }

    // MARK: - Handle Raw Stream Events

    private func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?
    ) {
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            return
        }
        if shouldHardBlockForMissingPolicyAck(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
            // Queue the event instead of silently dropping it.
            // It will be flushed when the policy_ack arrives.
            if let turn = resolveToolTraceTurn(conversationId: convId, providerId: pid) {
                if !policyAckFailedMessages.contains(turn.assistantMessageId) {
                    policyAckBlockedQueue[turn.assistantMessageId, default: []].append(
                        (type: t, payload: p, providerId: pid, conversationId: convId)
                    )
                }
            }
            return
        }
        if t == "tool_validation_error",
           isMCPEditRequiredViolation(payload: p) {
            var enriched = p
            enriched["status"] = "failed"
            if (enriched["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["title"] = "MCP-only editing policy violation"
            }
            if (enriched["detail"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["detail"] = "Edit requests must use the coderide MCP tools."
            }
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            emitMCPEditRequiredViolation(payload: enriched, conversationId: convId)
            return
        }
        if t == "turn_started" {
            streamingSegmentTurnIndex += 1
        }
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            let groupId = p["group_id"] ?? "reasoning-stream"
            if streamingReasoningConversationId != convId {
                streamingReasoningBlocks = []
                streamingSegments = []
                streamingSegmentTurnIndex = 0
            }
            if let idx = streamingReasoningBlocks.firstIndex(where: { $0.id == groupId }) {
                streamingReasoningBlocks[idx].text = Self.mergeReasoningText(
                    existing: streamingReasoningBlocks[idx].text,
                    incoming: output
                )
            } else {
                streamingReasoningBlocks.append(ReasoningBlock(id: groupId, text: output))
            }
            streamingReasoningText = streamingReasoningBlocks.map(\.text).joined(separator: "\n\n")
            streamingReasoningConversationId = convId

            let segId = "reasoning-\(streamingSegmentTurnIndex)"
            let currentBlockText = streamingReasoningBlocks.last(where: { $0.id == groupId })?.text ?? output
            if let segIdx = streamingSegments.firstIndex(where: { $0.id == segId }) {
                streamingSegments[segIdx].kind = .reasoning(currentBlockText)
            } else {
                streamingSegments.append(MessageSegment(id: segId, kind: .reasoning(currentBlockText)))
            }
        }
        if t == "coderide_show_task_panel" { enableTaskPanelIfNeeded() }
        if t == "coderide_show_swarm_panel", planFlowPhase != .building {
            showSwarmPanel = true
            if let swarmId = SwarmMetadata.swarmId(from: p) {
                selectedSwarmId = swarmId
            }
        }
        if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
            let n = s.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            swarmProgressStore.setSteps(n)
        }
        if t == "agent", let title = p["title"], let detail = p["detail"] {
            if detail == "started" {
                swarmProgressStore.markStarted(name: title)
            } else if detail == "completed" {
                swarmProgressStore.markCompleted(name: title)
            }
        }
        if t == "usage",
           let inpStr = p["input_tokens"], let outStr = p["output_tokens"],
           let inp = Int(inpStr), let out = Int(outStr) {
            if pid.hasSuffix("-api") {
                providerUsageStore.addApiUsage(
                    inputTokens: inp,
                    outputTokens: out,
                    model: p["model"] ?? "gpt-4o-mini"
                )
            } else if pid == "claude-cli" {
                let current = providerUsageStore.claudeUsage
                let merged = ClaudeUsage(
                    sessionCost: current?.sessionCost,
                    inputTokens: max(current?.inputTokens ?? 0, inp),
                    outputTokens: max(current?.outputTokens ?? 0, out),
                    cacheReadTokens: current?.cacheReadTokens,
                    cacheWriteTokens: current?.cacheWriteTokens,
                    totalDuration: current?.totalDuration
                )
                providerUsageStore.claudeUsage = merged
                providerUsageStore.claudeUsageMessage = nil
            }
            let prev = chatStore.conversation(for: convId)?.lastInputTokens ?? 0
            if inp > prev {
                chatStore.updateLastInputTokens(inp, for: convId)
            }
        }
        if t == "subagent_batch_done" {
            autoCompleteInProgressTodoAfterSubagents(status: p["status"] ?? "done")
            return // Don't record this synthetic event as a visible activity
        }
        recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
    }

    @MainActor
    private func autoCompleteInProgressTodoAfterSubagents(status: String) {
        let targetStatus: TodoStatus = status == "done" ? .done : .blocked
        let targetIDs = todoIDsToAutoCompleteAfterSubagentBatch(todos: todoStore.todos)
        for id in targetIDs {
            todoStore.setStatus(id: id, status: targetStatus)
        }
    }

    @MainActor
    private func processPolicyAckEvent(
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> [String: String] {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return payload
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return payload
        }

        let receivedHash = (payload["hash"] ?? payload["policy_hash"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var enriched = payload
        enriched["expected_hash"] = state.expectedHash

        if receivedHash == state.expectedHash {
            state.acknowledgedHash = receivedHash
            policyAckFailedMessages.remove(turn.assistantMessageId)
            enriched["status"] = "acknowledged"
            enriched["title"] = payload["title"] ?? "Policy acknowledged"
            enriched["detail"] = payload["detail"] ?? "Policy hash accepted"
        } else {
            enriched["status"] = "invalid"
            enriched["title"] = payload["title"] ?? "Policy acknowledgment invalid"
            enriched["detail"] = payload["detail"] ?? "Expected hash \(state.expectedHash)"
        }
        policyAckStateByMessage[turn.assistantMessageId] = state
        return enriched
    }

    @MainActor
    private func shouldHardBlockForMissingPolicyAck(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> Bool {
        guard agentsHardBlockEnabled else { return false }
        if isSwarmPolicyAckExemptProvider(providerId) || hasSwarmTraceMetadata(payload) {
            return false
        }
        guard ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload) else { return false }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return false
        }
        if policyAckFailedMessages.contains(turn.assistantMessageId) {
            return true
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return false
        }
        if state.isSatisfied { return false }
        if state.violationEmitted { return true }

        state.violationEmitted = true
        policyAckStateByMessage[turn.assistantMessageId] = state
        policyAckFailedMessages.insert(turn.assistantMessageId)
        policyAckBlockedQueue.removeValue(forKey: turn.assistantMessageId)
        emitPolicyAckViolation(
            expectedHash: state.expectedHash,
            incomingType: type,
            providerId: providerId,
            conversationId: conversationId
        )
        return true
    }

    @MainActor
    private func isSwarmPolicyAckExemptProvider(_ providerId: String) -> Bool {
        let normalized = providerId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty { return false }
        return normalized == "swarm-runtime-internal"
            || normalized == "code-review-multi-swarm"
            || normalized.hasPrefix("swarm-")
            || normalized.contains("multi-swarm")
    }

    @MainActor
    private func hasSwarmTraceMetadata(_ payload: [String: String]) -> Bool {
        return SwarmMetadata.isSwarmEvent(payload)
    }

    @MainActor
    private func routeDebugEvent(
        _ event: NormalizedEvent,
        payload: [String: String],
        eventConversationId: UUID?
    ) {
        if shouldHandleDebugStoreEvent(payload: payload, eventConversationId: eventConversationId) {
            applyDebugEventToActiveStore(event)
            persistDebugState(for: selectedConversationId)
            return
        }
        guard !SwarmMetadata.isSwarmEvent(payload), let eventConversationId else {
            return
        }
        pendingDebugEventsByConversation[eventConversationId, default: []].append(event)
    }

    @MainActor
    private func applyDebugEventToActiveStore(_ event: NormalizedEvent) {
        switch event {
        case .debugPhaseUpdate(let phase, let detail):
            handleDebugPhaseUpdate(phase: phase, detail: detail)
        case .debugUserRequest(let kind, let prompt):
            handleDebugUserRequest(kind: kind, prompt: prompt)
        case .debugResolved(let summary):
            handleDebugResolved(summary: summary)
        case .debugLog(let payload):
            handleDebugLogPayload(payload)
        case .debugHypothesize(let payload):
            handleDebugHypothesizePayload(payload)
        case .debugMark(let payload):
            handleDebugMarkPayload(payload)
        case .debugInstrument(let payload):
            handleDebugInstrumentPayload(payload)
        case .debugClean(let payload):
            handleDebugCleanPayload(payload)
        case .debugSession(let payload):
            handleDebugSessionPayload(payload)
        case .debugQuery(let payload):
            handleDebugQueryPayload(payload)
        default:
            break
        }
    }

    @MainActor
    private func persistDebugState(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStateByConversation[conversationId] = debugStore.snapshot()
    }

    @MainActor
    private func restoreDebugState(for conversationId: UUID?) {
        guard let conversationId else {
            debugStore.resetSession()
            return
        }
        if let snapshot = debugStateByConversation[conversationId] {
            debugStore.restore(from: snapshot)
        } else {
            debugStore.resetSession()
        }
    }

    @MainActor
    private func applyPendingDebugEvents(for conversationId: UUID?) {
        guard let conversationId,
              let pending = pendingDebugEventsByConversation.removeValue(forKey: conversationId),
              !pending.isEmpty
        else {
            return
        }
        for event in pending {
            applyDebugEventToActiveStore(event)
        }
        persistDebugState(for: conversationId)
    }

    @MainActor
    private func shouldHandleDebugStoreEvent(payload: [String: String], eventConversationId: UUID?) -> Bool {
        if SwarmMetadata.isSwarmEvent(payload) {
            return false
        }
        guard let selectedConversationId else {
            return false
        }
        guard let eventConversationId else {
            return false
        }
        return eventConversationId == selectedConversationId
    }

    @MainActor
    private func emitPolicyAckViolation(
        expectedHash: String,
        incomingType: String,
        providerId: String,
        conversationId: UUID?
    ) {
        let detail =
            "Missing required marker [CODERIDE:policy_ack|hash=\(expectedHash)] before event '\(incomingType)'."
        recordTaskActivity(
            type: "tool_execution_error",
            payload: [
                "title": "Policy acknowledgment required",
                "detail": detail,
                "status": "failed",
                "error_code": "policy_ack_missing",
                "expected_hash": expectedHash,
            ],
            providerId: providerId,
            conversationId: conversationId
        )
        appendTechnicalErrorMessage(
            "[Policy error] Mandatory AGENTS/SKILL acknowledgment missing. Emit [CODERIDE:policy_ack|hash=\(expectedHash)] before using tools.",
            in: conversationId
        )
        stopTaskForPolicyViolation(conversationId: conversationId)
    }

    @MainActor
    private func isMCPEditRequiredViolation(payload: [String: String]) -> Bool {
        let code = (payload["error_code"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return code == "mcp_edit_required"
    }

    @MainActor
    private func emitMCPEditRequiredViolation(payload: [String: String], conversationId: UUID?) {
        let detail = (payload["detail"] ?? "Edit requests must use the coderide MCP tools.")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        appendTechnicalErrorMessage(
            "[Policy error] \(detail)",
            in: conversationId
        )
        stopTaskForPolicyViolation(conversationId: conversationId)
    }

    /// Flush events that were queued while waiting for policy_ack.
    @MainActor
    private func flushPolicyAckBlockedQueue(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        guard let queued = policyAckBlockedQueue.removeValue(forKey: messageId), !queued.isEmpty else {
            return
        }
        for event in queued {
            recordTaskActivity(
                type: event.type,
                payload: event.payload,
                providerId: event.providerId,
                conversationId: event.conversationId
            )
        }
    }

    @MainActor
    private func stopTaskForPolicyViolation(conversationId: UUID?) {
        let didCancelTask = cancelRunTask(for: conversationId)
        if !didCancelTask {
            let scope = executionScopeForCurrentMode()
            executionController.terminate(scope: scope)
        }
        applyFlowCoordinatorState(for: conversationId) { $0.interrupt() }
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let conversationId {
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearStreamingReasoning(for: conversationId)
        }
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .failed)
        if conversationId == self.conversationId {
            cancelFallbackTurnStartEvent()
        }
        snapshotSubagentCardsAndEndTask(conversationId: conversationId)
        if conversationId == self.conversationId
            || activeBuildAgentConversationId == conversationId {
            activeBuildPlanConversationId = nil
            activeBuildAgentConversationId = nil
            resetPlanFlowAfterInterruption()
        }
    }

    static func shouldShowFinalChatActions(
        conversation: Conversation?,
        isLoadingForCurrentConversation: Bool
    ) -> Bool {
        guard !isLoadingForCurrentConversation else { return false }
        guard let conversation else { return false }
        guard conversation.messages.contains(where: { $0.role == .assistant }) else { return false }
        guard let lastMessage = conversation.messages.last else { return false }
        return lastMessage.role == .assistant && !lastMessage.isStreaming
    }

    static func mergeReasoningText(existing: String?, incoming: String) -> String {
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty else { return existing ?? "" }
        guard let existing, !existing.isEmpty else {
            return String(incoming.prefix(24_000))
        }

        if incoming == existing { return existing }
        if incoming.hasPrefix(existing) {
            return String(incoming.prefix(24_000))
        }
        if existing.hasPrefix(incoming) || existing.contains(incoming) {
            return existing
        }
        if incoming.contains(existing) {
            return String(incoming.prefix(24_000))
        }

        let overlap = reasoningSuffixPrefixOverlapLength(lhs: existing, rhs: incoming)
        if overlap > 0 {
            let suffixStart = incoming.index(incoming.startIndex, offsetBy: overlap)
            let merged = existing + String(incoming[suffixStart...])
            return String(merged.suffix(24_000))
        }

        let separator =
            existing.hasSuffix("\n") || incoming.hasPrefix("\n")
            ? "\n"
            : "\n\n"
        let merged = existing + separator + incoming
        return String(merged.suffix(24_000))
    }

    private static func reasoningSuffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        let maxOverlap = min(lhs.count, rhs.count, 1_024)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if lhs.suffix(size) == rhs.prefix(size) {
                return size
            }
        }
        return 0
    }

    private func clearStreamingReasoning(for conversationId: UUID?) {
        flushStreamingContent()
        guard let id = conversationId, streamingReasoningConversationId == id else { return }
        if let reasoning = streamingReasoningText, !reasoning.isEmpty {
            chatStore.saveReasoningToLastAssistant(reasoning: reasoning, in: id)
        }
        streamingReasoningText = nil
        streamingReasoningConversationId = nil
        streamingReasoningBlocks = []
        streamingSegments = []
        streamingSegmentTurnIndex = 0
    }

    private func clearPlanStreamingState() {
        flushPlanStreamingContent()
        planStreamingContent = ""
        pendingPlanStreamConversationId = nil
        pendingPlanStreamingContent = nil
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
    }

    private func shouldRoutePlanStream(to conversationId: UUID?) -> Bool {
        let hasContext = hasActivePlanContext(for: conversationId)
        return shouldRoutePlanStreamToPlanPanel(
            shouldRoutePlanStreamingToPanel: shouldRoutePlanStreamingToPanel,
            streamConversationId: conversationId,
            hasActivePlanContext: hasContext,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
    }

    private func updatePlanStreamingContent(_ content: String, conversationId: UUID?) {
        pendingPlanStreamConversationId = conversationId
        pendingPlanStreamingContent = content.count > 24_000
            ? String(content.suffix(24_000))
            : content

        // If a throttle is already scheduled, coalesce with latest text.
        if planStreamThrottleTask != nil { return }

        // Show first chunk without delay.
        flushPlanStreamingContent()

        // Coalesce and defer subsequent updates to reduce re-render churn.
        planStreamThrottleTask = Task {
            let delay = UInt64(planStreamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                flushPlanStreamingContent()
            }
        }
    }

    private func appendPlanStreamingContent(_ content: String, conversationId: UUID?) {
        updatePlanStreamingContent(content, conversationId: conversationId)
    }

    private func flushPlanStreamingContent() {
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
        guard let newContent = pendingPlanStreamingContent else { return }
        pendingPlanStreamingContent = nil
        pendingPlanStreamConversationId = nil
        planStreamingContent = newContent
    }

    private func buildWalkthroughMarkdown(
        canonicalTodos: [TodoItem],
        planBoard: PlanBoard?,
        agentMessages: [ChatMessage] = [],
        traceEvents: [ToolTraceEvent] = []
    ) -> String {
        var lines: [String] = ["## Build Complete", ""]
        if let goal = planBoard?.goal, !goal.isEmpty {
            lines.append("**Objective:** \(goal)")
            lines.append("")
        }

        // Steps with status
        let doneCount = canonicalTodos.filter { $0.status == .done }.count
        lines.append("### Steps (\(doneCount)/\(canonicalTodos.count) completed)")
        for todo in canonicalTodos {
            let icon = todo.status == .done ? "x" : " "
            lines.append("- [\(icon)] \(todo.title)")
            if !todo.linkedFiles.isEmpty {
                lines.append("  Files: \(todo.linkedFiles.joined(separator: ", "))")
            }
        }
        lines.append("")

        // Files changed (from trace events)
        let fileChangeTypes: Set<String> = ["file_change", "edit", "write", "create_file", "str_replace", "multi_edit"]
        let changedFiles = Set(
            traceEvents
                .filter { fileChangeTypes.contains($0.type) }
                .compactMap { $0.payload["file"] ?? $0.payload["path"] ?? $0.title }
                .map { url in
                    // Show relative path only
                    if let range = url.range(of: "Sources/") { return String(url[range.lowerBound...]) }
                    if let range = url.range(of: "Tests/") { return String(url[range.lowerBound...]) }
                    if let range = url.range(of: "CoderEngine/") { return String(url[range.lowerBound...]) }
                    return (url as NSString).lastPathComponent
                }
        ).sorted()
        if !changedFiles.isEmpty {
            lines.append("### Files Modified (\(changedFiles.count))")
            for file in changedFiles {
                lines.append("- `\(file)`")
            }
            lines.append("")
        }

        // Commands run
        let commands = traceEvents
            .filter { $0.type == "command_execution" }
            .compactMap { $0.payload["command"] ?? $0.title }
            .filter { !$0.isEmpty }
        if !commands.isEmpty {
            let uniqueCommands = Array(Set(commands.map { cmd in
                // Truncate long commands
                cmd.count > 80 ? String(cmd.prefix(77)) + "..." : cmd
            })).sorted().prefix(10)
            lines.append("### Commands Executed")
            for cmd in uniqueCommands {
                lines.append("- `\(cmd)`")
            }
            lines.append("")
        }

        // Agent narrative — the actual text the agent wrote during execution
        let narrativeBlocks = agentMessages
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { content in
                // Skip short auto-generated messages
                content.count > 40
            }
        if !narrativeBlocks.isEmpty {
            lines.append("### Execution Details")
            // Include meaningful agent text, capped to avoid giant walkthroughs
            let combined = narrativeBlocks.joined(separator: "\n\n---\n\n")
            let capped = combined.count > 6000 ? String(combined.suffix(6000)) : combined
            lines.append(capped)
        }

        return lines.joined(separator: "\n")
    }

    private func stripPlanCheckboxes(_ content: String) -> String {
        content.replacingOccurrences(
            of: #"(?m)^(\s*[-*]\s*)\[\s*[xX ]?\s*\]\s*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private func applyStreamingUpdate(
        content: String,
        conversationId: UUID?
    ) {
        let shouldSanitize = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let sanitizedContent = shouldSanitize ? stripPlanCheckboxes(content) : content
        let isBuildConversationForCurrentPlanFlow = shouldRoutePlanStream(to: conversationId)
        let shouldRouteToPlanPanel = isBuildConversationForCurrentPlanFlow

        if shouldRouteToPlanPanel {
            appendPlanStreamingContent(
                sanitizedContent,
                conversationId: conversationId
            )
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
            return
        }

        // Keep off-screen/background thread updates isolated from the visible stream throttle state.
        if conversationId != self.conversationId {
            chatStore.updateLastAssistantMessage(
                content: sanitizedContent,
                in: conversationId,
                persistImmediately: false
            )
            return
        }

        // Always store the latest content so we never lose data.
        pendingStreamContent = sanitizedContent
        pendingStreamConversationId = conversationId

        updateStreamingTextSegment(sanitizedContent)

        // If a throttle is already scheduled, let it pick up the latest content.
        if streamThrottleTask != nil { return }

        // Flush immediately for the first update (so the user sees something right away).
        flushStreamingContent()

        // Schedule the next flush after the throttle interval.
        streamThrottleTask = Task {
            let delay = UInt64(streamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                streamThrottleTask = nil
                if let pending = pendingStreamContent {
                    pendingStreamContent = nil
                    let shouldSanitizePending = isPlanBuildContext(
                        conversationId: pendingStreamConversationId,
                        phase: planFlowPhase,
                        activeBuildPlanConversationId: activeBuildPlanConversationId,
                        activeBuildAgentConversationId: activeBuildAgentConversationId
                    )
                    chatStore.updateLastAssistantMessage(
                        content: shouldSanitizePending ? stripPlanCheckboxes(pending) : pending,
                        in: pendingStreamConversationId,
                        persistImmediately: false
                    )
                    streamContentVersion &+= 1
                }
            }
        }
    }

    private func flushStreamingContent() {
        streamThrottleTask?.cancel()
        streamThrottleTask = nil
        guard let content = pendingStreamContent else { return }
        pendingStreamContent = nil
        let shouldSanitizePending = isPlanBuildContext(
            conversationId: pendingStreamConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let sanitizedContent = shouldSanitizePending ? stripPlanCheckboxes(content) : content
        chatStore.updateLastAssistantMessage(
            content: sanitizedContent,
            in: pendingStreamConversationId,
            persistImmediately: false
        )
        streamContentVersion &+= 1
    }

    private func updateStreamingTextSegment(_ content: String) {
        let segId = "text-\(streamingSegmentTurnIndex)"
        if content.isEmpty {
            streamingSegments.removeAll { $0.id == segId }
            return
        }
        if let idx = streamingSegments.firstIndex(where: { $0.id == segId }) {
            streamingSegments[idx].kind = .text(content)
        } else {
            streamingSegments.append(MessageSegment(id: segId, kind: .text(content)))
        }
    }

    // MARK: - Handle Stream Result (plan options + swarm delegation)

    private func handleStreamResult(
        conversationId streamConversationId: UUID,
        fullText: String,
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        prompt: String
    ) async {
        let isBuildContext = isPlanBuildContext(
            conversationId: streamConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let full = isBuildContext
            ? normalizeBuildFinalResponse(fullText)
            : fullText
        let fullLooksLikePlanPayload = looksLikePlanPayload(full)
        let shouldRoutePlanStreamToPanel = shouldRoutePlanStream(to: streamConversationId)
        let shouldHidePlanMarkdownForBuild =
            isBuildContext && shouldRoutePlanStreamToPanel
        let hasPlanContextForStreamConversation = hasActivePlanContext(for: streamConversationId)
        let shouldHidePlanMarkdown = shouldHidePlanMarkdownInChat(
            shouldRoutePlanStreamToPanel: shouldRoutePlanStreamToPanel,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            fullLooksLikePlanPayload: fullLooksLikePlanPayload,
            shouldHidePlanMarkdownForBuild: shouldHidePlanMarkdownForBuild,
            hasActivePlanContext: hasPlanContextForStreamConversation
        )
        if shouldHidePlanMarkdownForBuild,
           shouldAutoOpenPlanPanel(trigger: .flowStarted),
           !showPlanPanel
        {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
        let initialChatContent = shouldHidePlanMarkdown
            ? "Processing plan output in Plan Panel..."
            : full
        chatStore.updateLastAssistantMessage(
            content: initialChatContent,
            in: streamConversationId,
            persistImmediately: true
        )
        chatStore.setLastAssistantStreaming(false, in: streamConversationId)
        clearStreamingReasoning(for: streamConversationId)
        await trySummarizeIfNeeded(ctx: ctx)

        // Handle plan options parsing (safety net — multi-turn flow handles its own classification)
        if (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .analyzing
            && planFlowPhase != .questioning
            && planFlowPhase != .generating
            && planFlowPhase != .building
        {
            let classification = PlanOutputClassifier.classify(
                fullText: full,
                current: planFlowPhase,
                coderMode: coderMode,
                shouldRunPlanInline: shouldRunPlanInline
            )
            if classification.isConfident, let classificationState = classification.planningState {
                await MainActor.run {
                    planFlowPhase = classification.nextPhase
                    // Only update planningState for non-idle classifications;
                    // idle means the classifier found a signal (e.g. "no questions needed")
                    // but doesn't need to change the planning state.
                    if classificationState != .idle {
                        planningState = classificationState
                    }
                }
                if case .awaitingClarification = classificationState {
                    let summaryContent = "Clarifications needed to proceed with the plan. Open the Planning panel to answer the questions."
                    chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
                    await MainActor.run {
                        if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: false,
                                source: .automaticFlow
                            )
                        }
                    }
                }
                if case .awaitingChoice(_, let opts) = classificationState {
                    let board = PlanBoard.build(from: full, options: opts)
                    chatStore.setPlanBoard(board, for: streamConversationId)
                    let currentConv = chatStore.conversation(for: streamConversationId)
                    let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
                    let summaryContent = "Plan ready in Plan Panel: \(parsedSummary.title)"
                    chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
                    _ = planHistoryStore.createEntry(
                        conversationId: streamConversationId,
                        contextId: currentConv?.contextId,
                        contextFolderPath: currentConv?.contextFolderPath,
                        title: parsedSummary.title,
                        markdown: full,
                        options: opts,
                        chosenPath: board.chosenPath,
                        tags: [],
                        sourceMessageId: nil
                    )
                    inlinePlanSummaries.removeValue(forKey: streamConversationId)
                    if shouldRunPlanInline {
                        let contextId = currentConv?.contextId
                        let contextFolderPath = currentConv?.contextFolderPath
                        let planConvId = chatStore.getOrCreateConversationForMode(
                            contextId: contextId, contextFolderPath: contextFolderPath,
                            mode: .plan)
                        chatStore.setPlanBoard(board, for: planConvId)
                    }
                    await MainActor.run {
                        if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: false,
                                source: .automaticFlow
                            )
                        }
                    }
                }
            }
        }

        // After any agent turn with file edits (non-plan), add a Code Review todo
        let isPlanBuildContext = (planFlowPhase == .building || planFlowPhase == .readyToBuild)
        if !isPlanBuildContext,
           taskActivityStore.activities.contains(where: { $0.phase == .editing })
        {
            let alreadyHasReview = todoStore.todos.contains {
                $0.title == "Code Review & Test" && $0.status != .done
            }
            if !alreadyHasReview {
                await MainActor.run {
                    todoStore.upsertFromAgent(
                        id: nil,
                        title: "Code Review & Test",
                        status: .pending,
                        priority: .high,
                        notes: "Review changes and run tests",
                        activeForm: "Reviewing code and running tests",
                        linkedFiles: []
                    )
                }
            }
        }
    }

    private func createCheckpointBeforeTurn(
        conversationId: UUID?, workspaceContext: WorkspaceContext
    ) throws {
        guard let conversationId else { return }
        let pathStrings = workspaceContext.workspacePaths.map(\.path)
        do {
            let states = try checkpointGitStore.captureSnapshots(
                conversationId: conversationId, workspacePaths: pathStrings)
            chatStore.createCheckpoint(for: conversationId, gitStates: states)
        } catch {
            // Cursor-style fallback: valid chat checkpoint even outside a Git repository.
            if let gitError = error as? ConversationCheckpointGitStore.GitStoreError {
                switch gitError {
                case .notGitRepository:
                    chatStore.createCheckpoint(for: conversationId, gitStates: [])
                    return
                default:
                    throw error
                }
            }
            throw error
        }
    }

    private func appendTechnicalErrorMessage(_ message: String, in conversationId: UUID?) {
        let normalized = normalizeTechnicalErrorMessage(message)
        if let conversationId,
            let last = chatStore.conversation(for: conversationId)?.messages.last,
            last.role == .assistant,
            last.content == normalized
        {
            return
        }
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: normalized, isStreaming: false),
            to: conversationId
        )
    }

    private func normalizeTechnicalErrorMessage(_ message: String) -> String {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "[Error] Operation not completed. Try again."
        }
        let lower = raw.lowercased()
        if lower.contains("coderengine.coderengineerror error 0")
            || (lower.contains("operation couldn") && lower.contains("coderengine"))
        {
            return
                "[Runtime error] Operation not completed by CLI provider. Check authentication and usage limits, then try again."
        }
        return raw
    }

    private func userFacingStreamError(_ error: Error) -> String {
        if isNetworkError(error) && !networkMonitor.isPathSatisfied {
            return "[Connection lost] The network connection was interrupted. Reconnecting…"
        }
        let detail = String(describing: error)
        let normalized = normalizeTechnicalErrorMessage(detail)
        if normalized == detail.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "[Error] \(error.localizedDescription)"
        }
        return normalized
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let networkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
        ]
        if nsError.domain == NSURLErrorDomain && networkCodes.contains(nsError.code) {
            return true
        }
        let desc = String(describing: error).lowercased()
        return desc.contains("network connection was lost")
            || desc.contains("not connected to the internet")
            || desc.contains("the internet connection appears to be offline")
            || desc.contains("a data connection is not currently allowed")
    }

    private func isInterruptedStreamError(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        if executionController.runState == .stopping {
            return true
        }

        let normalized = String(describing: error).lowercased()
        if normalized.contains("cancellationerror")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
        {
            return true
        }

        return false
    }

    private func rewindConversation() {
        guard !isRewinding else { return }
        guard let convId = conversationId,
            let conv = chatStore.conversation(for: convId),
            let lastUserIndex = conv.messages.lastIndex(where: { $0.role == .user })
        else { return }
        let lastUserMessage = conv.messages[lastUserIndex]
        let checkpoint = chatStore.previousCheckpoint(conversationId: convId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: convId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: convId)
                }
            }

            // Try file restore only if we have git snapshots; on error continue
            // with chat-only rewind anyway (always-available behavior).
            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: convId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                var rewound: Bool
                if let checkpoint {
                    rewound = chatStore.rewindConversationState(
                        to: checkpoint.id, conversationId: convId)
                    if rewound {
                        // Make sure the user message is removed from the chat
                        // (it remains only in the input for editing).
                        rewound = chatStore.rewindConversationToMessageCount(
                            lastUserIndex, conversationId: convId)
                    }
                } else {
                    // Fallback without checkpoint: remove last user turn + response.
                    rewound = chatStore.rewindConversationToMessageCount(
                        lastUserIndex, conversationId: convId)
                }
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: convId)
                    isRewinding = false
                    return
                }

                // Cursor-style: bring the last user prompt back into the composer for editing.
                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (lastUserMessage.content == placeholderImageOnly) ? "" : lastUserMessage.content
                attachedComposerAttachments = composerAttachments(from: lastUserMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: convId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

    private func composerAttachments(from message: ChatMessage) -> [ComposerAttachment] {
        let baseAttachments: [ChatAttachment]
        if let attachments = message.attachments, !attachments.isEmpty {
            baseAttachments = attachments
        } else if let imagePaths = message.imagePaths, !imagePaths.isEmpty {
            baseAttachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            return []
        }

        return baseAttachments.compactMap { item in
            let url = URL(fileURLWithPath: item.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ComposerAttachment(
                kind: item.kind,
                url: url,
                originalName: item.originalName,
                mimeType: item.mimeType,
                sizeBytes: item.sizeBytes
            )
        }
    }

    private func rewindToMessage(at messageIndex: Int, conversationId: UUID) {
        guard !isRewinding else { return }
        guard let conv = chatStore.conversation(for: conversationId),
            messageIndex < conv.messages.count,
            conv.messages[messageIndex].role == .user
        else { return }
        let userMessage = conv.messages[messageIndex]
        let checkpoint = chatStore.checkpoint(forMessageIndex: messageIndex, conversationId: conversationId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: conversationId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: conversationId)
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: conversationId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                // Remove the user message from the chat (and everything after it) so it can be
                // edited in the input and resent without duplicates.
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: conversationId)
                    isRewinding = false
                    return
                }

                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (userMessage.content == placeholderImageOnly) ? "" : userMessage.content
                attachedComposerAttachments = composerAttachments(from: userMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: conversationId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

    private func linkedContextPaths() -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: todoStore.todos.flatMap(\.linkedFiles))
        if let board = chatStore.planBoard(for: conversationId) {
            ordered.append(contentsOf: board.steps.compactMap(\.targetFile))
        }
        var seen = Set<String>()
        let deduped = ordered.filter { seen.insert($0).inserted }
        guard let context = effectiveContext.context else { return deduped }
        return deduped.compactMap { ref in
            switch ContextPathResolver.resolve(reference: ref, context: context) {
            case .resolved(let path):
                return path
            case .ambiguous(let matches):
                return matches.first
            case .notFound:
                return nil
            }
        }
    }

    private func openChangedFile(_ repoRelativePath: String) {
        guard let gitRoot = gitPanelStore.gitRoot else { return }
        let absolutePath = URL(fileURLWithPath: gitRoot).appendingPathComponent(repoRelativePath)
            .path
        let gitService = GitService()
        openFilesStore.openFileWithDiff(absolutePath, gitRoot: gitRoot, gitService: gitService)
        selectMode(.ide)
    }

    private func streamingStatusText(for message: ChatMessage) -> String {
        guard message.isStreaming, message.role == .assistant else { return "" }
        let scopedActivities = scopedTaskActivities(for: conversationId)
        return TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scopedActivities
        )
    }

    private func updateSidebarTaskStatus() {
        guard let currentConversationId = conversationId,
              chatStore.isTaskActive(for: currentConversationId) else { return }
        let scopedActivities = scopedTaskActivities(for: currentConversationId)
        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scopedActivities
        )
        chatStore.setTaskStatus(status, for: currentConversationId)
    }

    @MainActor
    private func streamingDetailText(for message: ChatMessage, conversationId convId: UUID?) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        let scopedActivities = scopedTaskActivities(for: convId)
        if let fromActivities = TaskActivityStore.streamingDetailText(
            activities: scopedActivities,
            activeOperationsCount: scopedActiveOperationsCount(for: convId)
        ) {
            return fromActivities
        }
        if let fromContent = ChatStore.extractLastOperationalThinkingLine(from: message.content) {
            return fromContent
        }
        if convId == streamingReasoningConversationId, let reasoning = streamingReasoningText, !reasoning.isEmpty {
            let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                .last?
                .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
            if !lastLine.isEmpty {
                return lastLine.count > 80 ? String(lastLine.prefix(77)) + "…" : lastLine
            }
        }
        return nil
    }

    private func scopedTaskActivities(for targetConversationId: UUID?) -> [TaskActivity] {
        guard let targetConversationId else { return taskActivityStore.activities }
        let expected = targetConversationId.uuidString.lowercased()
        return taskActivityStore.activities.filter { activity in
            let tagged = (activity.payload["conversation_id"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return tagged.isEmpty || tagged == expected
        }
    }

    private func scopedActiveOperationsCount(for targetConversationId: UUID?) -> Int {
        let activities = scopedTaskActivities(for: targetConversationId)
        return activities.suffix(40)
            .filter { $0.isRunning && !SwarmMetadata.isSwarmEvent($0.payload) }
            .count
    }
}
