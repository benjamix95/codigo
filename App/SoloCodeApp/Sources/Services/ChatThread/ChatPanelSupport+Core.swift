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

    var color: Color {
        switch self {
        case .agent: return DesignSystem.Colors.agentColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .debug: return DesignSystem.Colors.debugColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .browser: return DesignSystem.Colors.browserColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }

    var iconName: String {
        switch self {
        case .agent: return "brain.head.profile"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .debug: return "ladybug.fill"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .browser: return "globe"
        case .mcpServer: return "server.rack"
        }
    }

    var shortLabel: String {
        switch self {
        case .agent: return "Agent"
        case .codeReviewMultiSwarm: return "Review"
        case .debug: return "Debug"
        case .plan: return "Plan"
        case .ide: return "IDE"
        case .browser: return "Browser"
        case .mcpServer: return "MCP"
        }
    }
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

func toolTraceTurnOutcome(
    pipelineSuccess: Bool,
    pipelineWasCancelled: Bool
) -> ToolTraceTurnOutcome {
    if pipelineSuccess { return .success }
    if pipelineWasCancelled { return .aborted }
    return .failed
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
    excludeCanonicalTodos: Bool = false,
    reviewTodoTitle: String = "Code Review & Test"
) -> [UUID] {
    let normalizedReviewTitle = normalizedTodoTitle(reviewTodoTitle)
    let isInScope = todoConversationScopeFilter(todos: todos, conversationId: conversationId)
    let inProgressCandidates = todos.filter {
        isInScope($0)
            && $0.source == .agent
            && !$0.isOperationalPlaceholder
            && $0.status == .inProgress
            && (!excludeCanonicalTodos || !$0.isPlanCanonical)
    }
    let prioritizedInProgress = inProgressCandidates.sorted { lhs, rhs in
        let lhsHasActiveForm = !lhs.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rhsHasActiveForm = !rhs.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if lhsHasActiveForm != rhsHasActiveForm { return lhsHasActiveForm && !rhsHasActiveForm }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdAt > rhs.createdAt
    }
    var ids = Set(prioritizedInProgress.prefix(1).map(\.id))
    if includePendingReviewTodo,
       let pendingReview = todos.first(where: {
           isInScope($0)
               && $0.source == .agent
               && !$0.isOperationalPlaceholder
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

func canScrollToTarget(
    _ target: AnyHashable,
    topAnchorId: String,
    bottomAnchorId: String,
    allowAnchorTargets: Bool,
    availableMessageIDs: Set<UUID>
) -> Bool {
    if let stringTarget = target as? String {
        guard allowAnchorTargets else { return false }
        return stringTarget == topAnchorId || stringTarget == bottomAnchorId
    }
    if let messageID = target as? UUID {
        return availableMessageIDs.contains(messageID)
    }
    return false
}

func shouldInvalidateChatTimelineForLiveMutation(eventType: String) -> Bool {
    switch eventType {
    case "todo_write", "todo_read", "plan_create", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_request_user_input":
        return true
    default:
        return false
    }
}

func requiresTodoPlanStartPolicy(providerId: String, coderMode: CoderMode) -> Bool {
    let normalized = providerId
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard coderMode == .agent else { return false }
    return normalized == "codex-cli" || normalized.hasPrefix("codex")
}

func isTodoLifecycleEvent(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "todo_write" || normalizedType == "todo_read" {
        return true
    }
    guard normalizedType == "mcp_tool_call" else { return false }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return tool == "coderide_todo_write" || tool == "todo_write"
        || tool == "coderide_todo_read" || tool == "todo_read"
}

func isPlanLifecycleEvent(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "plan_create"
        || normalizedType == "plan_request_user_input"
        || normalizedType == "plan_step_upsert"
        || normalizedType == "plan_step_batch_update"
        || normalizedType == "plan_step_reorder"
        || normalizedType == "plan_step_dependency_set"
        || normalizedType == "plan_set_walkthrough"
    {
        return true
    }
    guard normalizedType == "mcp_tool_call" else { return false }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return tool == "coderide_plan_create" || tool == "plan_create"
        || tool == "coderide_plan_request_user_input" || tool == "plan_request_user_input"
        || tool == "coderide_plan_step_upsert" || tool == "plan_step_upsert"
        || tool == "coderide_plan_step_batch_update" || tool == "plan_step_batch_update"
        || tool == "coderide_plan_step_reorder" || tool == "plan_step_reorder"
        || tool == "coderide_plan_step_dependency_set" || tool == "plan_step_dependency_set"
        || tool == "coderide_plan_set_walkthrough" || tool == "plan_set_walkthrough"
}

func isOperationalEventRequiringTodoPlanStartPolicy(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "policy_ack"
        || normalizedType == "activate_plan_mode"
        || normalizedType == "activate_debug_mode"
        || normalizedType == "turn_started"
        || normalizedType == "turn_completed"
        || normalizedType == "reasoning"
        || normalizedType == "usage"
        || normalizedType == "assistant_update"
        || normalizedType == "agent"
        || normalizedType == "subagent_text"
        || normalizedType == "subagent_batch_done"
        || normalizedType == "tool_validation_error"
        || normalizedType == "tool_execution_error"
        || normalizedType == "error"
    {
        return false
    }
    if isTodoLifecycleEvent(type: normalizedType, payload: payload)
        || isPlanLifecycleEvent(type: normalizedType, payload: payload)
    {
        return false
    }
    if normalizedType == "mcp_tool_call" {
        let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return isTodoGatedOperationalTool(tool)
    }
    if normalizedType == "command_execution"
        || normalizedType == "bash"
    {
        return true
    }
    if normalizedType.hasPrefix("web_search") || normalizedType.hasPrefix("web_fetch") {
        return false
    }
    return false
}

private func isTodoGatedOperationalTool(_ rawToolName: String) -> Bool {
    let tool = rawToolName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard !tool.isEmpty else { return false }

    if tool == "coderide_policy_ack" || tool == "policy_ack"
        || tool == "coderide_activate_plan_mode" || tool == "activate_plan_mode"
        || tool == "coderide_activate_debug_mode" || tool == "activate_debug_mode"
        || tool == "coderide_skill" || tool == "skill"
        || tool.hasPrefix("coderide_audit_") || tool.hasPrefix("audit_")
        || tool.contains("subagent_")
    {
        return false
    }

    let nonMutatingDiscoveryTools: Set<String> = [
        "coderide_read", "read",
        "coderide_read_range", "read_range",
        "coderide_list_dir", "list_dir",
        "list_mcp_resources",
        "list_mcp_resource_templates",
        "mcp_list_resources",
        "mcp_list_prompts",
        "coderide_find_files", "find_files",
        "coderide_glob", "glob",
        "coderide_grep", "grep",
        "coderide_codebase_search", "codebase_search",
        "coderide_semantic_search", "semantic_search",
        "coderide_find_symbol", "find_symbol",
        "coderide_find_references", "find_references",
        "coderide_file_outline", "file_outline",
        "coderide_git_diff", "git_diff",
        "coderide_web_search", "web_search",
        "coderide_web_fetch", "web_fetch",
        "read_thread_terminal",
    ]
    if nonMutatingDiscoveryTools.contains(tool) {
        return false
    }

    return true
}

func todoPlanStartPolicyViolation(
    state: ToolStartRequirementsState,
    type: String,
    payload: [String: String]
) -> (errorCode: String, title: String, detail: String)? {
    guard isOperationalEventRequiringTodoPlanStartPolicy(type: type, payload: payload) else {
        return nil
    }

    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let toolName = (payload["mcp_tool"] ?? payload["tool"] ?? normalizedType)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if !state.didSeeTodoWrite, !isTodoLifecycleEvent(type: normalizedType, payload: payload) {
        return (
            "todo_first_required",
            "Todo required before execution",
            "Emit todo_write before starting real execution with '\(toolName.isEmpty ? normalizedType : toolName)'."
        )
    }

    return nil
}

func shouldShowOperationEventInLinearChat(
    eventType: String,
    payload: [String: String],
    showTodoCard: Bool
) -> Bool {
    let type = eventType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if ["policy_ack", "usage", "reasoning", "turn_started", "turn_completed"].contains(type) {
        return false
    }
    if showTodoCard && (type == "todo_write" || type == "todo_read") {
        return false
    }
    if type == "todo_write" || type == "todo_read" {
        return false
    }
    if type == "mcp_tool_call" {
        let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if tool == "coderide_policy_ack" || tool == "policy_ack" {
            return false
        }
        if tool == "coderide_activate_plan_mode" || tool == "activate_plan_mode"
            || tool == "coderide_activate_debug_mode" || tool == "activate_debug_mode"
        {
            return false
        }
        if showTodoCard && (tool == "coderide_todo_write" || tool == "todo_write" || tool == "coderide_todo_read" || tool == "todo_read") {
            return false
        }
    }
    if type == "agent" || type == "subagent_text" || type == "subagent_batch_done" {
        return true
    }
    return ToolTraceVisibility.shouldDisplay(
        event: ToolTraceEvent(
            sequence: 0,
            timestamp: .distantPast,
            providerId: "",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: type,
            title: "",
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )
    )
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
    PlanOutputClassifier.classify(
        fullText: fullText,
        current: current,
        coderMode: coderMode,
        shouldRunPlanInline: shouldRunPlanInline
    ).nextPhase
}
