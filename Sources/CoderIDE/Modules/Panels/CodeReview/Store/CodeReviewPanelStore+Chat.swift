import CoderEngine
import Foundation

// MARK: - Independent Panel Chat

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
            kind: .plain,
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
        let sessionStore = chatSessionStore
        let sessionKey = chatSessionKey

        coordinator.runChatStream(
            provider: provider,
            prompt: prompt,
            context: context,
            onToken: { accumulated in
                sessionStore.updateMessage(id: assistantId, for: sessionKey) {
                    $0.content = accumulated
                }
            },
            onComplete: {
                sessionStore.updateMessage(id: assistantId, for: sessionKey) {
                    $0.isStreaming = false
                }
                sessionStore.setProcessing(false, startedAt: nil, for: sessionKey)
            },
            onError: { error in
                sessionStore.updateMessage(id: assistantId, for: sessionKey) {
                    $0.content = "Error: \(error)"
                    $0.isStreaming = false
                }
                sessionStore.setProcessing(false, startedAt: nil, for: sessionKey)
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
            persistChatState()
        }
    }

    /// Clear chat history.
    func clearChatHistory() {
        guard let activeChatThreadId else { return }
        chatSessionStore.deleteThread(activeChatThreadId, for: chatSessionKey)
    }

    func beginPanelActionOutput(
        title: String,
        detail: String? = nil,
        selectChatTab: Bool = true
    ) -> UUID {
        ensureActiveChatThread()
        if selectChatTab {
            selectTab(.chat)
        }
        appendChatMessage(
            ReviewPanelChatMessageFactory.commandInvocation(
                title: title,
                detail: detail
            )
        )
        let assistantId = UUID()
        appendChatMessage(ReviewPanelMessage(
            id: assistantId,
            role: .assistant,
            kind: .reviewRun,
            content: "",
            isStreaming: true
        ))
        return assistantId
    }

    func streamPanelActionOutput(id: UUID, event: StreamEvent) {
        switch event {
        case .textDelta(let delta):
            let current = chatMessages.first(where: { $0.id == id })?.content ?? ""
            updateChatMessage(id: id, content: current + delta)
        case .textReplace(let replacement):
            updateChatMessage(id: id, content: replacement)
        default:
            break
        }
    }

    func finishPanelActionOutput(id: UUID, fallbackContent: String? = nil) {
        if let fallbackContent,
           let message = chatMessages.first(where: { $0.id == id }),
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateChatMessage(id: id, content: fallbackContent)
        }
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        persistChatState()
    }

    func failPanelActionOutput(id: UUID, error: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = "Error: \(error)"
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        persistChatState()
    }

    func appendPanelSystemMessage(
        _ text: String,
        kind: ReviewPanelMessageKind = .statusNote,
        selectChatTab: Bool = false
    ) {
        if selectChatTab {
            selectTab(.chat)
        }
        let message: ReviewPanelMessage
        switch kind {
        case .findingMutation:
            message = ReviewPanelChatMessageFactory.findingUpdate(text: text)
        default:
            message = ReviewPanelMessage(
                role: .system,
                kind: kind,
                content: text
            )
        }
        appendChatMessage(message)
    }

    // MARK: - Private

    private func buildChatPrompt(userMessage: String) -> String {
        let snapshot = currentSnapshot
        let findingsCount = snapshot?.findings.count ?? 0
        let openCount = snapshot?.findings.filter { $0.status == .open }.count ?? 0

        var summary = "Phase: \(snapshot?.phase.rawValue ?? "none")"
        if let scope = snapshot?.scope {
            summary += "\nScope: \(scope.description)"
        }
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

    private func updateChatMessage(id: UUID, content: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        persistChatState()
    }

    private func finalizeChatStreamComplete(id: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    private func finalizeChatMessage(
        id: UUID,
        content: String,
        isError: Bool
    ) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    func appendChatMessage(_ message: ReviewPanelMessage) {
        chatMessages.append(message)
        persistChatState()
    }

    private func setChatProcessing(_ isProcessing: Bool, startedAt: Date?) {
        isChatProcessing = isProcessing
        chatStartedAt = startedAt
        persistChatState()
    }

    private func persistChatState() {
        chatSessionStore.replaceActiveState(
            ReviewPanelChatSessionState(
                messages: chatMessages,
                isProcessing: isChatProcessing,
                startedAt: chatStartedAt
            ),
            for: chatSessionKey
        )
    }

    private func ensureActiveChatThread() {
        if activeChatThreadId == nil {
            activeChatThreadId = chatSessionStore.createThread(for: chatSessionKey)
        }
    }
}
