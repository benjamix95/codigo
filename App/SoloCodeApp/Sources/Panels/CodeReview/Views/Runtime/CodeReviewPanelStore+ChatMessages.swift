import CoderEngine
import Foundation

// MARK: - Chat Message Operations

extension CodeReviewPanelStore {
    func sendChatMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatProcessing else { return }
        ensureActiveChatThread()
        let pinnedSessionId = panelSessionId ?? selectedSessionId
        if panelSessionId == nil, let pinnedSessionId {
            if !applyPanelIntent("bind_panel_session", value: pinnedSessionId) {
                panelSessionId = pinnedSessionId
            }
        }

        appendChatMessage(ReviewPanelMessage(
            role: .user,
            kind: .plain,
            content: trimmed
        ))

        let assistantId = UUID()
        let startedAt = Date()
        guard applyPanelChatStart(
            assistantId: assistantId,
            startedAt: startedAt
        ) else {
            appendPanelSystemMessage(
                ReviewPanelStateRustAdapter.runtimeUnavailableMessage,
                kind: .statusNote,
                selectChatTab: true
            )
            return
        }

        guard let provider = effectivePanelProvider else {
            finalizeChatMessage(
                id: assistantId,
                content: "No provider available. Please configure a provider.",
                isError: true
            )
            return
        }

        let prompt = buildChatPrompt(
            userMessage: normalizedPanelChatUserMessage(
                trimmed,
                selectedSessionId: pinnedSessionId
            ),
            sessionId: pinnedSessionId
        )
        let context = buildWorkspaceContext()

        coordinator.runChatStream(
            provider: provider,
            prompt: prompt,
            context: context,
            onEvent: { [weak self] event in
                self?.streamPanelActionOutput(
                    id: assistantId,
                    event: event,
                    runtime: .chat
                )
            },
            onFinish: { [weak self] result in
                guard let self else { return }
                if result.wasCancelled {
                    return
                }
                if let error = result.error {
                    _ = self.failPanelActionOutput(
                        id: assistantId,
                        error: error,
                        runtime: .chat,
                        wasCancelled: false
                    )
                    return
                }
                let outcome = self.finishPanelActionOutput(
                    id: assistantId,
                    runtime: .chat,
                    fallbackContent: "Chat response completed."
                )
                if outcome?.status == "completed" {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.syncStructuredFindingsFromChatResponse(
                            messageId: assistantId,
                            sessionId: pinnedSessionId
                        )
                    }
                }
            }
        )
    }

    func sendPresetMessage(_ preset: ReviewChatPreset) async {
        await sendChatMessage(preset.prompt)
    }

    func cancelChatStream() {
        coordinator.cancelChat()
        _ = applyPanelChatFinish(
            assistantId: nil,
            fallbackContent: nil,
            error: nil,
            wasCancelled: true,
            finishAllStreaming: true
        )
    }

    func clearChatHistory() {
        guard let activeChatThreadId else { return }
        chatSessionStore.deleteThread(activeChatThreadId, for: chatSessionKey)
    }

    func appendChatMessage(_ message: ReviewPanelMessage) {
        chatMessages.append(message)
        persistChatState()
    }

    func updateChatMessage(id: UUID, content: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        persistChatState()
    }

    func finalizeChatStreamComplete(id: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    func finalizeChatMessage(
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

    func appendVerifiedFindingSystemMessage(
        sessionId: String,
        findingId: String,
        title: String,
        detail: String? = nil,
        selectChatTab: Bool = false
    ) {
        if selectChatTab {
            selectTab(.chat)
        }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            appendPanelSystemMessage(
                detail.map { "\(title)\n\n\($0)" } ?? title,
                kind: .findingMutation,
                selectChatTab: false
            )
            return
        }
        appendChatMessage(
            ReviewPanelChatMessageFactory.findingUpdate(
                snapshot: snapshot,
                findingId: findingId,
                title: title,
                detail: detail
            )
        )
    }

    func appendReviewRunSectionLine(
        id: UUID,
        sectionTitle: String,
        line: String
    ) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }

        let separator = "\n---\n"
        let current = chatMessages[index].content
        let parts = current.components(separatedBy: separator)
        var logPart = parts.first ?? ""
        let verdictPart = parts.count > 1
            ? parts.dropFirst().joined(separator: separator)
            : ""

        let heading = "### \(sectionTitle)"

        // Deduplicate: skip if this exact line already exists in the section
        if isDuplicateLine(trimmedLine, inSection: sectionTitle, ofLog: logPart) {
            return
        }

        if !logPart.contains(heading) {
            // Section doesn't exist — append new section at end of logPart
            if !logPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logPart += "\n\n"
            }
            logPart += heading + "\n" + trimmedLine + "\n"
        } else {
            // Section exists — insert line at end of this specific section
            logPart = insertLineInSection(
                logPart: logPart,
                heading: heading,
                line: trimmedLine
            )
        }

        let rebuilt = verdictPart.isEmpty
            ? logPart.trimmingCharacters(in: .whitespacesAndNewlines)
            : logPart.trimmingCharacters(in: .whitespacesAndNewlines)
                + separator + verdictPart
        chatMessages[index].content = rebuilt
        persistChatState()
    }

}
