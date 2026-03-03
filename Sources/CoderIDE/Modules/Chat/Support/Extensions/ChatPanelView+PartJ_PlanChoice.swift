import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func trySummarizeIfNeeded(ctx: WorkspaceContext) async {
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

    internal func resolveActiveModelForContext() -> String {
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

    internal func resolvedContextWindowSizeForSummarize(model: String) -> Int {
        let normalized = model.lowercased()
        if normalized.contains("gemini") { return 1_048_576 }
        if normalized.contains("gpt-5") || normalized.contains("codex") { return 200_000 }
        if normalized.contains("claude") { return 200_000 }
        return ContextEstimator.contextSize(for: providerRegistry.selectedProviderId, model: model)
    }

    internal func runSummarize(provider: any LLMProvider, ctx: WorkspaceContext) async {
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
    internal func delegateToAgent() {
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
    internal func preferredRealProvider() -> (any LLMProvider)? {
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

    internal func resolvePreferredRealProvider() -> (any LLMProvider)? {
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
    internal func submitPlanClarificationAnswers(_ submission: PlanClarificationSubmission) {
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
    internal func selectPlanChoice(
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
    internal func handleCustomPlanResponseSelection(
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
        planningState = .idle
        planFlowPhase = .idle
        clearPlanStreamingState()
        inputText = "/plan \(mergedRequest)"
        isInputFocused = true
        sendMessage()
    }

}
