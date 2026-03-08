import CoderEngine
import Foundation

// MARK: - Chat Session Management

extension CodeReviewPanelStore {

    /// Send a user message in the panel chat and stream a response.
    /// This is completely independent from the main ChatStore.
    func sendChatMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatProcessing else { return }
        ensureActiveChatThread()

        appendChatMessage(ReviewPanelMessage(
            role: .user,
            kind: .plain,
            content: trimmed
        ))

        // Create streaming assistant message
        let assistantId = UUID()
        appendChatMessage(ReviewPanelMessage(
            id: assistantId,
            role: .assistant,
            kind: .reviewRun,
            content: "",
            isStreaming: true
        ))
        let startedAt = Date()
        setChatProcessing(true, startedAt: startedAt)

        // Resolve provider - use the currently selected provider
        guard let provider = effectivePanelProvider else {
            finalizeChatMessage(
                id: assistantId,
                content: "No provider available. Please configure a provider.",
                isError: true
            )
            return
        }

        // Build contextual prompt
        let prompt = buildChatPrompt(userMessage: trimmed)
        let context = buildWorkspaceContext()

        coordinator.runChatStream(
            provider: provider,
            prompt: prompt,
            context: context,
            onEvent: { [weak self] event in
                self?.streamPanelActionOutput(id: assistantId, event: event)
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.finishPanelActionOutput(
                    id: assistantId,
                    fallbackContent: "Chat response completed."
                )
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.syncStructuredFindingsFromChatResponse(messageId: assistantId)
                    self.setChatProcessing(false, startedAt: nil)
                }
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.failPanelActionOutput(id: assistantId, error: error)
                self.setChatProcessing(false, startedAt: nil)
            }
        )
    }

    /// Send a preset prompt.
    func sendPresetMessage(_ preset: ReviewChatPreset) async {
        await sendChatMessage(preset.prompt)
    }

    /// Cancel the current chat stream.
    func cancelChatStream() {
        coordinator.cancelChat()
        setChatProcessing(false, startedAt: nil)

        // Mark last assistant message as not streaming
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].role == .assistant,
           chatMessages[lastIndex].isStreaming
        {
            chatMessages[lastIndex].isStreaming = false
            if chatMessages[lastIndex].content.isEmpty {
                chatMessages[lastIndex].content = "Cancelled."
            }
            if chatMessages[lastIndex].kind == .reviewRun {
                ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[lastIndex])
            }
            persistChatState()
        }
    }

    /// Clear chat history.
    func clearChatHistory() {
        guard let activeChatThreadId else { return }
        chatSessionStore.deleteThread(activeChatThreadId, for: chatSessionKey)
    }

    // MARK: - Private Helpers

    func buildChatPrompt(userMessage: String) -> String {
        let snapshot = currentSnapshot
        let findingsCount = snapshot?.findings.count ?? 0
        let openCount = snapshot?.findings.filter { $0.status == .open }.count ?? 0
        let candidateCount = snapshot?.candidates.count ?? 0
        let patchCount = snapshot?.patches.count ?? 0

        var summary = "Phase: \(snapshot?.phase.rawValue ?? "none")"
        if let scope = snapshot?.scope {
            summary += "\nScope: \(scope.description)"
        }
        summary += "\nCandidates: \(candidateCount)"
        summary += "\nPatches: \(patchCount)"
        if findingsCount > 0 {
            let critCount = snapshot?.findings
                .filter { $0.severity == .critical }.count ?? 0
            let warnCount = snapshot?.findings
                .filter { $0.severity == .warning }.count ?? 0
            summary += "\nFindings breakdown: \(critCount) critical, \(warnCount) warning"
        }

        // Include recent findings in context
        let findingsContext: String
        if let findings = snapshot?.findings.prefix(10), !findings.isEmpty {
            let lines = findings.map { f in
                let line = f.lineNumber.map { ":\($0)" } ?? ""
                return "[\(f.severity.rawValue)] \(f.filePath)\(line) - \(f.message)"
            }
            findingsContext = "\nRecent findings:\n" + lines.joined(separator: "\n")
        } else {
            findingsContext = ""
        }

        return ReviewPanelCoordinator.chatContextPrompt(
            userMessage: userMessage,
            sessionSummary: summary + findingsContext,
            findingsCount: findingsCount,
            openCount: openCount
        )
    }

    func setChatProcessing(_ isProcessing: Bool, startedAt: Date?) {
        isChatProcessing = isProcessing
        chatStartedAt = startedAt
        persistChatState()
    }

    func persistChatState() {
        chatSessionStore.replaceActiveState(
            ReviewPanelChatSessionState(
                messages: chatMessages,
                isProcessing: isChatProcessing,
                startedAt: chatStartedAt
            ),
            for: chatSessionKey
        )
    }

    func ensureActiveChatThread() {
        if activeChatThreadId == nil {
            activeChatThreadId = chatSessionStore.createThread(for: chatSessionKey)
        }
    }

    func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
