import Foundation
import SwiftUI

extension PlanPanelView {
    func isPlanHistoryEntryAllowedForCurrentConversationThread(_ entry: PlanHistoryEntry) -> Bool {
        guard let currentConversationId = conversationId,
              let currentConversation = chatStore.conversation(for: currentConversationId) else {
            return false
        }
        let sourceConversation = chatStore.conversation(for: entry.conversationId)
        return isPlanHistoryEntryCompatibleWithCurrentThread(
            entryConversationId: entry.conversationId,
            currentConversationId: currentConversationId,
            entryThreadRootConversationId: sourceConversation?.threadRootConversationId,
            currentThreadRootConversationId: currentConversation.threadRootConversationId
        )
    }

    var canonicalPlanTodos: [TodoItem] {
        todoStore.canonicalTodos(for: conversationId)
    }

    var thinSeparator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border.opacity(0.4))
            .frame(height: 0.5)
    }

    func resolvedPreviewContent(for entry: PlanHistoryEntry) -> String {
        preferredPlanPanelHistoryContent(
            markdown: entry.markdown,
            chosenPath: entry.chosenPath,
            fallbackTitle: entry.title
        )
    }

    func selectedHistoryEntryForConversation() -> PlanHistoryEntry? {
        guard let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId) else { return nil }
        guard let conversationId,
              let currentConversation = chatStore.conversation(for: conversationId) else {
            return nil
        }
        let isCompatible = isPlanHistoryEntryCompatibleWithCurrentContext(
            entry: selected,
            currentConversationId: conversationId,
            currentContextId: currentConversation.contextId,
            currentContextFolderPath: currentConversation.contextFolderPath
        )
        guard isCompatible else { return nil }
        return isPlanHistoryEntryAllowedForCurrentConversationThread(selected) ? selected : nil
    }

    func latestPlanHistoryEntry() -> PlanHistoryEntry? {
        if let selected = selectedHistoryEntryForConversation() {
            return selected
        }
        guard let conversationId else { return nil }
        return planHistoryStore.findLatestEntry(for: conversationId)
    }

    func resolvedBuildContent(for entry: PlanHistoryEntry) -> String? {
        let chosen = entry.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chosen.isEmpty ? nil : chosen
    }

    func firstOption(byId options: [PlanOption]) -> PlanOption? {
        options.min(by: { $0.id < $1.id })
    }

    func resolveBuildChoice() -> (text: String, isFallback: Bool)? {
        let preferLiveBoard = shouldPreferLivePlanBoardOverHistory(
            phase: planFlowPhase,
            planningState: planningState
        )
        if let board = chatStore.planBoard(for: conversationId) {
            if let liveBoardChoice = fallbackPlanBuildContent(
                goal: board.goal,
                chosenPath: board.chosenPath,
                steps: board.steps
            ) {
                return (liveBoardChoice, board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            if preferLiveBoard {
                return nil
            }
        }
        if let selected = selectedHistoryEntryForConversation() {
            if let chosen = resolvedBuildContent(for: selected) {
                return (chosen, false)
            }
            return nil
        }
        return nil
    }

    func selectedOptionId(in options: [PlanOption]) -> Int? {
        guard !options.isEmpty else { return nil }
        if let board = chatStore.planBoard(for: conversationId),
           let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty,
           let match = options.first(where: { normalizedPlanText($0.fullText) == normalizedPlanText(chosen) })
        {
            return match.id
        }
        if let selected = selectedHistoryEntryForConversation(),
           let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty,
           let match = options.first(where: { normalizedPlanText($0.fullText) == normalizedPlanText(chosen) })
        {
            return match.id
        }
        return nil
    }

    func selectedOptionIdForHistoryEntry(_ entry: PlanHistoryEntry) -> Int? {
        guard !entry.options.isEmpty else { return nil }
        guard let chosen = entry.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chosen.isEmpty else { return nil }
        return entry.options.first(where: {
            normalizedPlanText($0.fullText) == normalizedPlanText(chosen)
        })?.id
    }

    func normalizedPlanText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func downloadCurrentPlan() {
        if let entry = latestPlanHistoryEntry() {
            let content = resolvedPreviewContent(for: entry).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                savePlanToFile(content: content, suggestedName: planFileName)
                return
            }
        }

        guard let board = chatStore.planBoard(for: conversationId) else { return }
        let content: String
        if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty {
            content = chosen
        } else if let first = firstOption(byId: board.options) {
            content = first.fullText
        } else {
            content = "# \(board.goal)\n\n"
        }
        savePlanToFile(content: content, suggestedName: planFileName)
    }

    func downloadPlan(_ entry: PlanHistoryEntry) {
        let content = resolvedPreviewContent(for: entry)
        let conversationTitle = chatStore.conversation(for: conversationId)?.title
        let suggestedName = makePlanFileName(
            preferredPlanTitle: entry.title,
            fallbackConversationTitle: conversationTitle
        )
        savePlanToFile(content: content, suggestedName: suggestedName)
    }
}
