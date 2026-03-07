import CoderEngine
import Foundation

// MARK: - Independent Panel Chat

extension CodeReviewPanelStore {

    /// Send a user message in the panel chat and stream a response.
    /// This is completely independent from the main ChatStore.
    func sendChatMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatProcessing else { return }

        // Add user message
        let userMessage = ReviewPanelMessage(
            role: .user,
            content: trimmed
        )
        chatMessages.append(userMessage)

        // Create streaming assistant message
        let assistantId = UUID()
        let assistantMessage = ReviewPanelMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isStreaming: true
        )
        chatMessages.append(assistantMessage)
        isChatProcessing = true
        chatStartedAt = Date()

        // Resolve provider - use the currently selected provider
        guard let provider = providerRegistry.selectedProvider else {
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
            onToken: { [weak self] accumulated in
                self?.updateChatMessage(id: assistantId, content: accumulated)
            },
            onComplete: { [weak self] in
                self?.finalizeChatStreamComplete(id: assistantId)
            },
            onError: { [weak self] error in
                self?.finalizeChatMessage(
                    id: assistantId,
                    content: "Error: \(error)",
                    isError: true
                )
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
        isChatProcessing = false
        chatStartedAt = nil

        // Mark last assistant message as not streaming
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].role == .assistant,
           chatMessages[lastIndex].isStreaming
        {
            chatMessages[lastIndex].isStreaming = false
            if chatMessages[lastIndex].content.isEmpty {
                chatMessages[lastIndex].content = "Cancelled."
            }
        }
    }

    /// Clear chat history.
    func clearChatHistory() {
        chatMessages.removeAll()
        isChatProcessing = false
        chatStartedAt = nil
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
    }

    private func finalizeChatStreamComplete(id: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        isChatProcessing = false
        chatStartedAt = nil
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
        isChatProcessing = false
        chatStartedAt = nil
    }
}
