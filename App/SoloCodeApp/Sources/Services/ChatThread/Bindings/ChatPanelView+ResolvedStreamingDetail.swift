import CoderEngine
import Foundation

extension ChatPanelView {
    /// Sottotitolo operativo per Planning: primo todo in corso / prossimo aperto, altrimenti step plan board.
    internal func planningNextMoveSubtitle(for conversationId: UUID?) -> String? {
        guard let conversationId else { return nil }
        let todos = todoStore.displayTodosForChat(for: conversationId)
        if let t = todos.first(where: { $0.status == .inProgress }) {
            return Self.nonEmptyTrimmedLine(t.title)
        }
        if let t = todos.first(where: { $0.status == .pending || $0.status == .blocked }) {
            return Self.nonEmptyTrimmedLine(t.title)
        }
        guard let board = chatStore.planBoard(for: conversationId), !board.steps.isEmpty else {
            return nil
        }
        if let s = board.steps.first(where: { $0.status == .running }) {
            return Self.nonEmptyTrimmedLine(s.title)
        }
        if let s = board.steps.first(where: { $0.status == .pending }) {
            return Self.nonEmptyTrimmedLine(s.title)
        }
        return nil
    }

    /// Unica sorgente per footer streaming in chat, snapshot e overlay todo composer.
    internal func resolvedStreamingDetail(
        activeAssistant: ChatMessage?,
        conversationId convId: UUID?,
        scopedActivities: [TaskActivity],
        activeOperationsCount: Int
    ) -> String? {
        guard let convId,
              let message = activeAssistant,
              message.isStreaming,
              message.role == .assistant else { return nil }
        let suppressReasoning = isReasoningSuppressedForProvider(
            resolvedTurnProviderId(for: convId)
        )

        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scopedActivities
        )

        let base: String? = {
            // `assistant_update` is operational/live response progress, not reasoning.
            // Even when provider reasoning is suppressed (e.g. codex-cli), the footer
            // should still reflect the latest assistant progress detail.
            if let assistantUpdate = TaskActivityStore.assistantUpdateText(in: scopedActivities),
               let line = ChatStore.sanitizedStreamingDetailLine(assistantUpdate) {
                return line
            }
            if let fromActivities = TaskActivityStore.streamingDetailText(
                activities: scopedActivities,
                activeOperationsCount: activeOperationsCount
            ), let line = ChatStore.sanitizedStreamingDetailLine(fromActivities) {
                return line
            }
            if !suppressReasoning,
               let fromContent = ChatStore.extractLastOperationalThinkingLine(from: message.content),
               let line = ChatStore.sanitizedStreamingDetailLine(fromContent) {
                return line
            }
            if !suppressReasoning,
               let codexLine = streaming.codexLastReasoningLine,
               !codexLine.isEmpty,
               convId == conversationId,
               let line = ChatStore.sanitizedStreamingDetailLine(codexLine) {
                return line
            }
            if !suppressReasoning,
               convId == streaming.streamingReasoningConversationId,
               let reasoning = streaming.streamingReasoningText,
               !reasoning.isEmpty {
                let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                    .last?
                    .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
                if !lastLine.isEmpty, let line = ChatStore.sanitizedStreamingDetailLine(lastLine, ellipsis: "…") {
                    return line
                }
            }
            return nil
        }()

        return mergePlanningDetail(status: status, base: base, conversationId: convId)
    }

    private func mergePlanningDetail(status: String, base: String?, conversationId: UUID) -> String? {
        guard status == "Planning next move" else { return base }
        guard let planLine = planningNextMoveSubtitle(for: conversationId) else { return base }
        if base == nil || base?.isEmpty == true { return planLine }
        if let b = base, Self.isGenericPlanningToolDetail(b) { return planLine }
        return base
    }

    private static func nonEmptyTrimmedLine(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func isGenericPlanningToolDetail(_ s: String) -> Bool {
        let l = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return true }
        if l == "todo_write" || l == "todo_read" { return true }
        if l.contains("plan_step") || l.hasPrefix("plan_") { return true }
        if l == "mcp_tool_call" || l == "coderide_todo_read" || l == "coderide_todo_write" { return true }
        return false
    }
}
