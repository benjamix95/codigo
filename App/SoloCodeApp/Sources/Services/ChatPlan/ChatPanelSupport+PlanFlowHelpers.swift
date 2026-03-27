import AppKit
import CoderEngine
import os
import SwiftUI
import UniformTypeIdentifiers

enum PlanScreeningDecision: Equatable {
    case planNeeded
    case noPlanNeeded
    case unknown
}

func parsePlanScreeningDecision(from text: String) -> PlanScreeningDecision {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if normalized.hasSuffix("NO_PLAN_NEEDED") {
        return .noPlanNeeded
    }

    if normalized.hasSuffix("PLAN_NEEDED") {
        return .planNeeded
    }

    return .unknown
}

func planScreeningStatusMessage(for decision: PlanScreeningDecision) -> String {
    switch decision {
    case .planNeeded, .unknown:
        return "Starting codebase analysis..."
    case .noPlanNeeded:
        return "No structured plan is needed for this request. Answering directly…"
    }
}

private enum PlanQuestionToolEpochStore {
    static let state = OSAllocatedUnfairLock(initialState: [UUID: Int]())

    static func epoch(for conversationId: UUID) -> Int {
        state.withLock { $0[conversationId] ?? 0 }
    }

    static func increment(for conversationId: UUID) -> Int {
        state.withLock { store in
            let next = (store[conversationId] ?? 0) + 1
            store[conversationId] = next
            return next
        }
    }
}

func planQuestionToolEpoch(for conversationId: UUID) -> Int {
    PlanQuestionToolEpochStore.epoch(for: conversationId)
}

@discardableResult
func incrementPlanQuestionToolEpoch(
    for conversationId: UUID,
    globalEpoch: inout Int
) -> Int {
    globalEpoch += 1
    return PlanQuestionToolEpochStore.increment(for: conversationId)
}

func normalizedPlanStreamingSnapshot(
    _ raw: String,
    maxLength: Int = 24_000
) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.suffix(maxLength))
}

func clarificationQuestionsMarkdownFromSnapshot(_ raw: String) -> String? {
    let normalized = normalizedPlanStreamingSnapshot(raw)
    guard !normalized.isEmpty else { return nil }
    guard PlanOptionsParser.parseClarificationQuestionnaire(from: normalized) != nil else {
        return nil
    }
    return normalized
}

func clarificationQuestionsMarkdownForRestore(
    _ raw: String,
    isBuildScopedConversation: Bool
) -> String? {
    guard !isBuildScopedConversation else { return nil }
    return clarificationQuestionsMarkdownFromSnapshot(raw)
}

func clarificationsNeededSection(from text: String) -> String? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    guard let regex = try? NSRegularExpression(
        pattern: #"(?im)^\s*#{1,3}\s*clarifications?\s*needed\s*:?\s*$"#
    ) else {
        return nil
    }
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    guard let match = regex.firstMatch(in: normalized, range: range),
          let headerRange = Range(match.range, in: normalized) else {
        return nil
    }
    let section = String(normalized[headerRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return section.isEmpty ? nil : section
}

func shouldAllowPlanToggleDeactivation(phase: PlanFlowPhase) -> Bool {
    switch phase {
    case .analyzing, .questioning, .generating, .building:
        return false
    case .idle, .proposalReady, .readyToBuild:
        return true
    }
}

func restoredPlanBuildPhase(
    conversationId: UUID?,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> PlanFlowPhase? {
    guard let conversationId else { return nil }
    guard conversationId == activeBuildPlanConversationId
        || conversationId == activeBuildAgentConversationId else {
        return nil
    }
    return .building
}

func resolveClarificationIdentitySeed(
    planClarificationCycles: Int,
    planConversationId: UUID?,
    globalEpoch: Int
) -> Int {
    let scopedEpoch = planConversationId.map { planQuestionToolEpoch(for: $0) } ?? globalEpoch
    return max(planClarificationCycles, scopedEpoch)
}

func shouldDisablePlanToggleWhenPanelCloses(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode,
    hasActiveBuildSession: Bool = false
) -> Bool {
    guard coderMode != .plan else { return false }
    guard planningState == .idle else { return false }
    if hasActiveBuildSession { return false }
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
        if streamConversationId == activeBuildPlanConversationId { return true }
        return false
    }

    if currentConversationId != nil {
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
    guard shouldRoutePlanStreamingToPanel else { return false }
    guard let streamConversationId else { return false }
    if hasActivePlanContext { return true }
    if phase == .building {
        if streamConversationId == activeBuildPlanConversationId { return true }
        if streamConversationId == activeBuildAgentConversationId { return true }
    }
    return false
}
