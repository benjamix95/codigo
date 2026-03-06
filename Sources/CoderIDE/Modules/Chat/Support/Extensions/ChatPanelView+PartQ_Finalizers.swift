import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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

    internal static func reasoningSuffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        let maxOverlap = min(lhs.count, rhs.count, 1_024)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if lhs.suffix(size) == rhs.prefix(size) {
                return size
            }
        }
        return 0
    }

    internal func clearStreamingReasoning(for conversationId: UUID?) {
        flushStreamingContent()
        guard let id = conversationId else { return }
        let hadInlineReasoning = streamingReasoningConversationId == id
        let hasSeparateThinkingMessages =
            !(reasoningMessageIdByConversationAndGroup[id]?.isEmpty ?? true)
        if hadInlineReasoning,
           !hasSeparateThinkingMessages,
           let reasoning = streamingReasoningText,
           !reasoning.isEmpty
        {
            chatStore.saveReasoningToLastAssistant(reasoning: reasoning, in: id)
        }
        resetReasoningMessageState(for: id)
        codexLastReasoningLine = nil
        chatStore.removeTrailingEmptyAssistantMessages(in: id)
        if hadInlineReasoning || hasSeparateThinkingMessages {
            streamingReasoningText = nil
            streamingReasoningConversationId = nil
            streamingReasoningBlocks = []
            streamingSegments = []
            streamingSegmentTurnIndex = 0
        }
    }

    internal func clearPlanStreamingState() {
        flushPlanStreamingContent()
        if let targetConversationId = conversationId {
            planStreamingContentByConversation[targetConversationId] = ""
            planStreamingContent = ""
            if pendingPlanStreamConversationId == targetConversationId {
                pendingPlanStreamConversationId = nil
                pendingPlanStreamingContent = nil
            }
        } else {
            planStreamingContentByConversation.removeAll()
            planStreamingContent = ""
            pendingPlanStreamConversationId = nil
            pendingPlanStreamingContent = nil
        }
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
    }

    internal func shouldRoutePlanStream(to conversationId: UUID?) -> Bool {
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

    internal func updatePlanStreamingContent(_ content: String, conversationId: UUID?) {
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

    internal func appendPlanStreamingContent(_ content: String, conversationId: UUID?) {
        updatePlanStreamingContent(content, conversationId: conversationId)
    }

    internal func flushPlanStreamingContent() {
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
        guard let newContent = pendingPlanStreamingContent else {
            if let currentConversationId = conversationId {
                planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
            }
            return
        }
        let targetConversationId = pendingPlanStreamConversationId
        pendingPlanStreamingContent = nil
        pendingPlanStreamConversationId = nil
        if let targetConversationId {
            planStreamingContentByConversation[targetConversationId] = newContent
        }
        if let currentConversationId = conversationId {
            planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
        } else if targetConversationId == nil {
            planStreamingContent = newContent
        }
    }

    internal func buildWalkthroughMarkdown(
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
        if canonicalTodos.isEmpty {
            lines.append("- No canonical steps recorded for this build.")
        } else {
            for todo in canonicalTodos {
                let icon = todo.status == .done ? "x" : " "
                lines.append("- [\(icon)] \(todo.title)")
                if !todo.linkedFiles.isEmpty {
                    lines.append("  Files: \(todo.linkedFiles.joined(separator: ", "))")
                }
            }
        }
        lines.append("")

        // Files changed (from successful file-mutation trace events)
        let changedFiles = touchedFilePathsFromTraceEvents(traceEvents, maxCount: 200)
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
    // MARK: - Handle Stream Result (plan options + swarm delegation)

}
