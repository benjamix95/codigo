import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func autoTodoTitle(for activity: TaskActivity) -> String {
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

    internal func autoTodoLinkedFiles(from payload: [String: String]) -> [String] {
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

    internal func shouldAcceptTodoWrite(_ todo: TodoWritePayload, conversationId: UUID?) -> Bool {
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
        let runtimeScope = todoStore.runtimeScopeFilter(for: conversationId)
        let hasExistingAgentTodo = todoStore.todos.contains {
            $0.source == .agent
                && !$0.isPlanCanonical
                && runtimeScope($0)
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

    internal func shouldAcceptTodoRead(conversationId: UUID?) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return true
        }
        let isRuntimeInScope = todoStore.runtimeScopeFilter(for: conversationId)
        let isCanonicalInScope = todoStore.canonicalScopeFilter(for: conversationId)
        guard todoStore.todos.contains(where: { item in
            if item.isPlanCanonical {
                return isCanonicalInScope(item)
            }
            return item.source == .agent && isRuntimeInScope(item)
        }) else {
            return false
        }
        return hasOperationalActivityInCurrentTurn(conversationId: conversationId)
    }

    internal func hasOperationalActivityInCurrentTurn(conversationId: UUID?) -> Bool {
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

    internal func currentAssistantMessageIdForTrace(conversationId: UUID) -> UUID? {
        if let active = activeToolTraceTurnsByConversation[conversationId] {
            return active.assistantMessageId
        }
        return chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id
    }

    internal func isOperationalTraceActivity(_ activity: TaskActivity) -> Bool {
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

    internal func isOperationalTraceEvent(_ event: ToolTraceEvent) -> Bool {
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

    internal func isPlaceholderTodoTitle(_ rawTitle: String) -> Bool {
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
}
