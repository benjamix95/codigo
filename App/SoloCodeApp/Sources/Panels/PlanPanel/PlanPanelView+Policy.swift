import CoderEngine
import Foundation

func isPlanBuildEnabled(
    phase: PlanFlowPhase,
    hasBuildChoice: Bool,
    allowIdleRebuild: Bool = false,
    providerExecutionCapable: Bool = true
) -> Bool {
    guard providerExecutionCapable else { return false }
    switch phase {
    case .proposalReady, .readyToBuild:
        return true
    case .idle:
        return allowIdleRebuild && hasBuildChoice
    case .analyzing, .questioning, .generating, .building:
        return false
    }
}

func shouldAllowIdleRebuildFromMainBuildAction(
    phase: PlanFlowPhase,
    hasBuildChoice: Bool
) -> Bool {
    phase == .idle && hasBuildChoice
}

func hasExecutablePlanBuildChoice(resolvedBuildContent: String?) -> Bool {
    guard let resolvedBuildContent else { return false }
    let normalized = resolvedBuildContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return false }
    guard PlanOptionsParser.hasRequiredTodoHeader(normalized) else { return false }
    return !PlanOptionsParser.extractTodosFromOptionText(normalized).isEmpty
}

func planBuildDisabledReason(
    phase: PlanFlowPhase,
    hasBuildChoice: Bool,
    providerExecutionCapable: Bool
) -> String? {
    switch phase {
    case .idle:
        return "No plan"
    case .analyzing:
        return "Analyzing..."
    case .questioning:
        return "Answer questions first"
    case .generating:
        return "Generating..."
    case .building:
        return "Building..."
    case .proposalReady, .readyToBuild:
        break
    }
    if !hasBuildChoice {
        return "No option selected"
    }
    if !providerExecutionCapable {
        return "Auth required"
    }
    return nil
}

func hasPlanContext(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    hasPlanBoard: Bool,
    hasSelectedHistoryEntry: Bool
) -> Bool {
    if [.analyzing, .questioning, .generating, .proposalReady, .readyToBuild, .building].contains(phase) {
        return true
    }
    if planningState != .idle {
        return true
    }
    return hasPlanBoard || hasSelectedHistoryEntry
}

func shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: Bool) -> Bool {
    hasPlanContext
}

func shouldPreferLivePlanBoardOverHistory(
    phase: PlanFlowPhase,
    planningState: PlanningState
) -> Bool {
    if planningState != .idle {
        return true
    }
    switch phase {
    case .proposalReady, .readyToBuild, .building:
        return true
    case .idle, .analyzing, .questioning, .generating:
        return false
    }
}

func clarificationWizardIdentityKey(
    for questionsMarkdown: String,
    seed: Int = 0
) -> String {
    let normalized = questionsMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    let content = normalized.isEmpty ? questionsMarkdown : normalized
    return "plan-clarification-wizard-\(max(0, seed))-\(content.count)-\(stablePlanSnapshotContentHash(content))"
}

func isPlanHistoryEntryCompatibleWithCurrentContext(
    entry: PlanHistoryEntry,
    currentConversationId: UUID?,
    currentContextId: UUID?,
    currentContextFolderPath: String?
) -> Bool {
    guard let currentConversationId else { return false }
    if currentContextId == nil && currentContextFolderPath == nil {
        return entry.conversationId == currentConversationId
    }
    let matchesContext = currentContextId != nil && entry.contextId == currentContextId
    let matchesFolder = currentContextFolderPath != nil && entry.contextFolderPath == currentContextFolderPath
    return matchesContext || matchesFolder
}

func isPlanHistoryEntryCompatibleWithCurrentThread(
    entryConversationId: UUID,
    currentConversationId: UUID?,
    entryThreadRootConversationId: UUID?,
    currentThreadRootConversationId: UUID?
) -> Bool {
    guard let currentConversationId else { return false }
    if entryConversationId == currentConversationId { return true }
    guard let entryThreadRootConversationId,
          let currentThreadRootConversationId else {
        return false
    }
    return entryThreadRootConversationId == currentThreadRootConversationId
}

func stablePlanSnapshotContentHash(_ content: String) -> UInt64 {
    var hash: UInt64 = 5381
    for byte in content.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return hash
}

func makePlanFileName(
    preferredPlanTitle: String?,
    fallbackConversationTitle: String?
) -> String {
    let resolvedTitle = normalizedPlanFileTitleCandidate(preferredPlanTitle)
        ?? normalizedPlanFileTitleCandidate(fallbackConversationTitle)
        ?? "plan"
    let slug = resolvedTitle
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "_")
        .prefix(40)
    let finalSlug = slug.isEmpty ? "plan" : String(slug)
    return "\(finalSlug).plan.md"
}

func preferredPlanPanelHistoryContent(
    markdown: String,
    chosenPath: String?,
    fallbackTitle: String
) -> String {
    if let chosen = chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !chosen.isEmpty {
        return chosen
    }
    let trimmedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedMarkdown.isEmpty {
        return markdown
    }
    let title = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return "# \(title.isEmpty ? "Plan" : title)\n\n(No plan content available.)"
}

func preferredPlanPanelOptionContent(
    chosenPath: String?,
    options: [PlanOption]
) -> String? {
    guard !options.isEmpty else { return nil }
    let normalizedChosen = chosenPath?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) ?? ""
    if !normalizedChosen.isEmpty,
       let matched = options.first(where: {
           $0.fullText
               .trimmingCharacters(in: .whitespacesAndNewlines)
               .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) == normalizedChosen
       }) {
        return matched.fullText
    }
    return options.min(by: { $0.id < $1.id })?.fullText
}

func preferredPlanPanelDisplayContent(
    preferLiveBoard: Bool,
    liveBoard: PlanBoard?,
    planningState: PlanningState,
    selectedHistoryContent: String?
) -> String? {
    let normalizedHistoryContent = selectedHistoryContent?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !preferLiveBoard,
       let normalizedHistoryContent,
       !normalizedHistoryContent.isEmpty,
       let selectedHistoryContent {
        return selectedHistoryContent
    }

    guard let liveBoard else { return nil }
    if case .awaitingChoice(_, let options) = planningState,
       let preferredOptionContent = preferredPlanPanelOptionContent(
           chosenPath: liveBoard.chosenPath,
           options: options
       ) {
        return preferredOptionContent
    }
    if let chosen = liveBoard.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !chosen.isEmpty {
        return chosen
    }
    if let first = liveBoard.options.min(by: { $0.id < $1.id }) {
        return first.fullText
    }
    return nil
}

func fallbackPlanBuildContent(
    goal: String,
    chosenPath: String?,
    steps: [PlanStep]
) -> String? {
    if let chosen = chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !chosen.isEmpty {
        return chosen
    }
    let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSteps = steps
        .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !normalizedGoal.isEmpty || !normalizedSteps.isEmpty else { return nil }

    let title = normalizedGoal.isEmpty ? "Execution Plan" : normalizedGoal
    let todoLines = normalizedSteps.isEmpty
        ? ["- [ ] Follow the generated plan"]
        : normalizedSteps.map { "- [ ] \($0)" }
    return """
    # \(title)

    ## Todo
    \(todoLines.joined(separator: "\n"))
    """
}

private func normalizedPlanFileTitleCandidate(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    guard !normalized.isEmpty else { return nil }
    return normalized
}

func makePlanRenderSnapshotCacheKey(content: String, canonicalTodos: [TodoItem]) -> String {
    let todosFingerprint = canonicalTodos
        .sorted { $0.id.uuidString < $1.id.uuidString }
        .map { todo in
            let updatedAtMs = Int(todo.updatedAt.timeIntervalSince1970 * 1_000)
            return "\(todo.id.uuidString)|\(todo.status.rawValue)|\(updatedAtMs)"
        }
        .joined(separator: ";")
    return "\(content.count)-\(stablePlanSnapshotContentHash(content))|\(todosFingerprint)"
}

func filterPlanTraceActivitiesForConversation(
    _ activities: [TaskActivity],
    conversationId: UUID?
) -> [TaskActivity] {
    guard let conversationId else { return activities }
    let scopedId = conversationId.uuidString.lowercased()
    return activities.filter { activity in
        canonicalConversationScope(from: activity.payload) == scopedId
    }
}
