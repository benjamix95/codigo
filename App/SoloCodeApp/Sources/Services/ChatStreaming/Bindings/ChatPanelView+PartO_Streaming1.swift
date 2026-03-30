import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func buildPrompt(
        userText: String,
        shouldRunPlanInline: Bool,
        planningStateOverride: PlanningState? = nil
    ) -> String {
        var prompt =
            userText.isEmpty
            ? "[The user attached an image. Analyze it and respond.]" : userText
        let effectivePlanningState = planningStateOverride ?? planningState

        // Plan mode: response to clarification questions → include context to proceed
        if shouldUseClarificationPrompt(
            coderMode: coderMode,
            planningState: effectivePlanningState,
            shouldRunPlanInline: shouldRunPlanInline
        ),
            case .awaitingClarification(let questions) = effectivePlanningState
        {
            prompt = """
            The user has answered your clarification questions.

            User's answers:
            \(userText.isEmpty ? "[No text provided]" : userText)

            The original questions were:
            \(questions)

            Next steps:
            1. Perform ADDITIONAL codebase analysis based on these answers using the same project tools and subagents available in Agent mode.
            2. Mutating tools remain blocked until the user presses Build. Restrict yourself to analysis, planning, read/search, MCP inspection, and subagent investigation.
            3. If blocked by a hard missing decision, call `plan_request_user_input` with structured questions.
            4. Otherwise proceed directly to generate ONE definitive plan with ## Plan: Title and ## Todo sections.
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
            - `debug_request_user` with kind question|reproduce|fix_confirmation and a concrete prompt.
            - `debug_session` with action start|export|stop when the lifecycle requires it.
            - `debug_snapshot`, `debug_hypothesize`, `debug_test_check`, `debug_timeline`, `debug_resolve`.
            Legacy `debug_panel` is invalid and must not be used.
            Keep debug artifacts tracked through `debug_mark`, `debug_instrument`, `debug_log`, `debug_query`, `debug_clean`.
            Canonical closeout order: `debug_clean` -> `debug_timeline` -> `debug_session action=export` -> `debug_resolve` -> `debug_session action=stop`.
            """
            prompt = debugModeContract + "\n\n" + prompt
        }
        let isPlanningDiscoveryFlow =
            (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .building

        if isPlanningDiscoveryFlow {
            let planningInstructions = """
            **Planning mode uses the same runtime contract as Agent mode.**

            Planning contract:
            - You may use the same project tools, MCP tools, and subagents available in Agent mode.
            - Before Build, you are under a planning guard: do NOT mutate files, run mutating commands, apply patches, or execute implementation steps.
            - Read/search/inspection/orchestration/subagent investigation are allowed.
            - Produce a normal linear chat response. Do not hide the plan behind panel-only state.
            - Ask clarifications ONLY when blocked by a hard missing decision.
            - If blocked, call `plan_request_user_input` with:
              * `questions` JSON array (1-3 questions)
              * each question with `prompt`, `options` (2-4), optional `multi_select`
              * options as objects with `label`, optional `description`, optional `recommended`
            - When using `plan_request_user_input`, the actual questions must remain visible in the chat timeline.
            - If the request is implementable with reasonable assumptions, skip questions and produce the final plan in this same turn.

            Final plan format:
            ## Plan: Title
            Description, rationale, trade-offs.
            ## Todo
            - [ ] Step 1
            - [ ] Step 2

            Mermaid:
            - Include a ```mermaid diagram when it helps visualize architecture, data flow, or implementation dependencies.

            Additional rules:
            - Do not start execution on your own. The user alone triggers Build.
            - After Build, execution will continue in the same chat thread.
            - Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) during planning.
            - Never combine clarification questions and the final ## Plan in the same response.

            Expected behavior:
            - First gather enough context.
            - Then either ask blocking questions, or produce the definitive plan.
            - If the user adds more constraints before Build, update the plan instead of executing it.

            Mermaid guidelines:
            When analyzing problems or creating plans, include a mermaid diagram when useful to visualize:
            - Architecture and component relationships
            - Data flows and event pipelines
            - Implementation step dependencies
            """
            prompt = planningInstructions + "\n\n" + prompt
        } else if ProviderSupport.isAgentCompatibleProvider(id: providerRegistry.selectedProviderId) {
                let isDebugUX = coderMode == .debug || showDebugPanel
                let baseInstructions: String = {
                    if isDebugUX {
                        return """
                        **Debug session (composer addendum):** Follow the `[DEBUG MODE ACTIVE]` contract above. Prioritize `debug_*` tools and direct `read`/`grep`/`semantic_search`. Do not default to spawning multiple `subagent_explorer` calls—only if parallel exploration clearly helps after initial debug context. TodoWrite is optional until the fix is genuinely multi-step; skip mandatory reviewer/testWriter rounds until you have substantive code changes to validate.
                        Prefer MCP plan tools for plan tracking (`plan_create`, `plan_step_upsert`, `plan_step_batch_update`,
                        `plan_step_reorder`, `plan_step_dependency_set`, `plan_set_walkthrough`) when also tracking plan work.
                        If MCP tools are unavailable, fallback marker:
                        \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
                        For code searches with rg, you can emit markers with results:
                        \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:line]
                        Read files in parallel batches (max 8 per batch) when broad context is needed. To track the batch you can emit:
                        \(CoderIDEMarkers.readBatchPrefix)count=8|files=FileA.swift,FileB.swift|group_id=batch-1]
                        For concurrent web searches (max 4 queries in parallel), emit status markers:
                        \(CoderIDEMarkers.webSearchPrefix)queryId=q1|query=swift concurrency|status=started|group_id=web-1]
                        """
                    }
                    return """
                    **Todo Workflow (use only when truly needed):**
                    1. Start with analysis (read/search) first. Initial codebase analysis is allowed before any todo creation.
                    2. If the task is simple (single action or <=2 concrete operations), do NOT emit todo markers.
                    3. If the task is genuinely multi-step, create ONE coherent todo list after analysis with only concrete, executable steps.
                    3b. For multi-step execution, emit the first \(CoderIDEMarkers.todoWritePrefix) update AFTER analysis but BEFORE any implementation, file modification, command that changes state, or other operational tool action.
                    4. Never create placeholder todos (forbidden examples: "Task", "Analysis", "Step 1", "Setup task panel", "Todo update").
                    5. Emit \(CoderIDEMarkers.showTaskPanel) only when a real todo list exists or when the user explicitly asks.
                    6. During execution, update status only for real todos: in_progress before work, done after completion.
                    7. Emit \(CoderIDEMarkers.todoRead) only for resume/reconciliation when needed, never as a default first action.
                    8. If MCP is available and external/domain capabilities are needed, call native MCP tools directly by name. Use `mcp_call` only as a fallback for tools not registered natively.
                    9. When MCP is used, explicitly report which MCP servers and MCP tools were used.
                    10. If context contains a required marker `[CODERIDE:policy_ack|hash=...]`, emit it once before any operational tool action. Emit the tool call directly; do NOT preface it with user-facing filler like "Ricevuto" or "Ingerisco la policy".
                    11. If SoloCode native `subagent_*` tools are available in the live schema, treat them as the canonical delegation path and use them first. Start directly with `subagent_*` when delegation is warranted; do NOT emit a natural-language preamble before those tool calls. Do NOT switch to provider-native fork/collaboration APIs when `subagent_*` is already exposed. If provider-native subagent/task capability exists but `subagent_*` does not, you may use the provider-native path. Never tell the user that fork/fork_context is unavailable; silently fall back to `subagent_*` or direct tools. Do NOT use `coderide_subagent_*` launch shims as a proxy for real child execution. For independent workstreams, prefer 2-5 `subagent_*` calls in the same round.
                    12. For implementation tasks, always run `subagent_reviewer` + `subagent_testWriter` before finalizing.
                    13. Do NOT auto-open the swarm/subagent panel. Emit \(CoderIDEMarkers.showSwarmPanel) only when the user explicitly asks to open/focus that panel.
                    14. For local code discovery/inspection, prefer dedicated tools (`read`/`grep`/`semantic_search` or aliases like `coderide_read`/`coderide_grep`/`coderide_semantic_search`) and avoid `bash` commands such as `cat`, `rg`, `grep`, `find` unless those dedicated tools fail first.
                    Prefer MCP plan tools for plan tracking (`plan_create`, `plan_step_upsert`, `plan_step_batch_update`,
                    `plan_step_reorder`, `plan_step_dependency_set`, `plan_set_walkthrough`).
                    Keep `plan_step_update` only as legacy fallback compatibility.
                    If MCP tools are unavailable, fallback marker:
                    \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
                    For code searches with rg, you can emit markers with results:
                    \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:line]
                    Read files in parallel batches (max 8 per batch) when broad context is needed. To track the batch you can emit:
                    \(CoderIDEMarkers.readBatchPrefix)count=8|files=FileA.swift,FileB.swift|group_id=batch-1]
                    For concurrent web searches (max 4 queries in parallel), emit status markers:
                    \(CoderIDEMarkers.webSearchPrefix)queryId=q1|query=swift concurrency|status=started|group_id=web-1]
                    """
                }()
                prompt = baseInstructions + "\n" + prompt
                let scopedTodos = todoStore.displayTodosForChat(for: conversationId)
                if !scopedTodos.isEmpty {
                    let todoSection = scopedTodos.sorted { $0.status.rank < $1.status.rank }
                        .map { t -> String in
                            let check = t.status == .done ? "x" : " "
                            let trimmedNotes = t.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                            let notesSuffix = trimmedNotes.isEmpty ? "" : " — \(trimmedNotes)"
                            let linkedPreview = t.linkedFiles.prefix(8)
                            let linkedFilesSuffix: String
                            if linkedPreview.isEmpty {
                                linkedFilesSuffix = ""
                            } else {
                                let joined = linkedPreview.joined(separator: ", ")
                                let overflow = t.linkedFiles.count > linkedPreview.count ? ", ..." : ""
                                linkedFilesSuffix = " [files: \(joined)\(overflow)]"
                            }
                            return "- [\(check)] \(t.title) (\(t.status.rawValue))\(notesSuffix)\(linkedFilesSuffix)"
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

    internal func recentConversationContextForPrompt(maxMessages: Int = 30, maxCharsPerMessage: Int = 2500) -> String {
        chatStore.buildPromptContext(
            conversationId: conversationId,
            maxMessages: maxMessages,
            maxCharsPerMessage: maxCharsPerMessage,
            includeMemorySummary: false
        )
    }

    // MARK: - Handle Raw Stream Events

    internal func isCodexProvider(_ providerId: String) -> Bool {
        ChatReasoningPresentationPolicy.isCodexProvider(providerId)
    }

    internal func reasoningPresentationMode(providerId: String) -> ChatReasoningPresentationMode {
        ChatReasoningPresentationPolicy.mode(
            providerId: providerId,
            separateCodexThinkingMessagesEnabled: separateCodexThinkingMessagesEnabled
        )
    }

    internal func shouldSplitThinkingMessages(providerId: String) -> Bool {
        reasoningPresentationMode(providerId: providerId) == .separateMessages
    }

    internal func isReasoningSuppressedForProvider(_ providerId: String) -> Bool {
        reasoningPresentationMode(providerId: providerId) == .suppressed
    }

    internal func shouldUseLinearChat(providerId: String) -> Bool {
        guard codexLinearChatEnabled else { return false }
        return isCodexProvider(providerId)
    }

    @MainActor
    internal func resetReasoningMessageState(for conversationId: UUID?) {
        guard let conversationId else { return }
        streaming.reasoningMessageIdByConversationAndGroup.removeValue(forKey: conversationId)
    }

    @MainActor
    internal func upsertSeparateThinkingMessage(
        output: String,
        groupId: String,
        conversationId: UUID?
    ) {
        guard let conversationId else { return }
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return }

        var groupMap = streaming.reasoningMessageIdByConversationAndGroup[conversationId] ?? [:]
        if let messageId = groupMap[groupId] {
            let existingContent = chatStore.conversation(for: conversationId)?
                .messages
                .first(where: { $0.id == messageId })?
                .content
            let mergedContent = Self.mergeReasoningText(existing: existingContent, incoming: trimmedOutput)
            chatStore.updateAssistantMessage(
                messageId: messageId,
                content: mergedContent,
                in: conversationId,
                persistImmediately: false
            )
            if conversationId == self.conversationId {
                streaming.streamContentVersion &+= 1
            }
            return
        }

        let messageId = UUID()
        groupMap[groupId] = messageId
        streaming.reasoningMessageIdByConversationAndGroup[conversationId] = groupMap

        let thinkingMessage = ChatMessage(
            id: messageId,
            role: .assistant,
            content: trimmedOutput,
            isStreaming: false
        )
        if let streamingAssistantId = chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant && $0.isStreaming })?
            .id
        {
            chatStore.insertMessage(
                thinkingMessage,
                before: streamingAssistantId,
                in: conversationId
            )
        } else {
            chatStore.addMessage(thinkingMessage, to: conversationId)
        }
        if conversationId == self.conversationId {
            streaming.streamContentVersion &+= 1
        }
    }

    @MainActor
    internal func splitStreamingMessageForNewTurn(conversationId: UUID?, providerId: String) {
        guard let conversationId else { return }
        flushStreamingContent()

        guard let conv = chatStore.conversation(for: conversationId),
              let currentMsg = conv.messages.last(where: { $0.role == .assistant && $0.isStreaming })
        else { return }

        let trimmedContent = currentMsg.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        chatStore.setLastAssistantStreaming(false, in: conversationId)

        let newId = UUID()
        chatStore.addMessage(
            ChatMessage(id: newId, role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )
        startToolTraceTurn(conversationId: conversationId, assistantMessageId: newId, providerId: providerId)
        pipelineIntegrationService.retargetAssistantMessage(
            for: conversationId,
            assistantMessageId: newId,
            turnId: newId.uuidString
        )
        streaming.codexLastReasoningLine = nil

        if conversationId == self.conversationId {
            streaming.streamContentVersion &+= 1
        }
    }

}
