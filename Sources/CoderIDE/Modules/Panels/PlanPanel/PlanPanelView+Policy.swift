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
        let payloadConversationId = activity.payload["conversation_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return payloadConversationId == scopedId
    }
}
