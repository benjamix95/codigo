import CoderEngine
import Foundation

// MARK: - Action Output & Event Processing

extension CodeReviewPanelStore {

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
        case .started:
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Review stream started"
            )
        case .completed:
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Review stream completed"
            )
        case .textDelta(let delta):
            appendTextDelta(id: id, delta: delta)
        case .textReplace(let replacement):
            replaceResponseSection(id: id, replacement: replacement)
        case .raw(let type, let payload):
            handleRawReviewRunEvent(id: id, type: type, payload: payload)
        case .error(let message):
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Error: \(message)"
            )
        }
    }

    // MARK: - Response Message (separate bubble)

    /// Finds or creates a dedicated response message that follows
    /// the review-run activity message. The response is rendered
    /// as its own chat bubble with full markdown support.
    private func responseMessageIndex(
        for activityId: UUID
    ) -> Int {
        // Look for an existing response message right after the activity
        if let activityIndex = chatMessages.firstIndex(
            where: { $0.id == activityId }
        ) {
            let nextIndex = activityIndex + 1
            if nextIndex < chatMessages.count,
               chatMessages[nextIndex].role == .assistant,
               chatMessages[nextIndex].kind == .plain
            {
                return nextIndex
            }
            // Create a new response message
            let responseMessage = ReviewPanelMessage(
                role: .assistant,
                kind: .plain,
                content: "",
                isStreaming: true
            )
            chatMessages.insert(responseMessage, at: nextIndex)
            return nextIndex
        }
        return chatMessages.count - 1
    }

    /// Appends a text delta to the separate response message.
    private func appendTextDelta(id: UUID, delta: String) {
        let index = responseMessageIndex(for: id)
        chatMessages[index].content += delta
        persistChatState()
    }

    /// Replaces the content of the separate response message.
    private func replaceResponseSection(
        id: UUID,
        replacement: String
    ) {
        let index = responseMessageIndex(for: id)
        chatMessages[index].content = replacement
        persistChatState()
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

        // Also finalize the separate response message if it exists
        let nextIndex = index + 1
        if nextIndex < chatMessages.count,
           chatMessages[nextIndex].role == .assistant,
           chatMessages[nextIndex].kind == .plain
        {
            chatMessages[nextIndex].isStreaming = false
        }
        persistChatState()
    }

    func failPanelActionOutput(id: UUID, error: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = "Error: \(error)"
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])

        // Also finalize the separate response message if it exists
        let nextIndex = index + 1
        if nextIndex < chatMessages.count,
           chatMessages[nextIndex].role == .assistant,
           chatMessages[nextIndex].kind == .plain
        {
            chatMessages[nextIndex].isStreaming = false
        }
        persistChatState()
    }

    // MARK: - Raw Event Handling

    func handleRawReviewRunEvent(
        id: UUID,
        type: String,
        payload: [String: String]
    ) {
        ingestRawReviewActivity(type: type, payload: payload)
        syncTodoIfNeeded(type: type, payload: payload)

        guard let formatted = formattedReviewRunEvent(type: type, payload: payload) else {
            return
        }

        if formatted.sectionTitle == "Response" {
            // Response content goes into the separate response message
            appendTextDelta(id: id, delta: formatted.line + "\n")
        } else {
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: formatted.sectionTitle,
                line: formatted.line
            )
        }
    }

    func ingestRawReviewActivity(
        type: String,
        payload: [String: String]
    ) {
        let enrichedPayload = enrichedReviewRawPayload(
            type: type, payload: payload
        )
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: effectivePanelProviderId
                ?? "review-panel",
            type: type,
            payload: enrichedPayload
        )
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.taskActivityStore.addEnvelope(envelope)
            for event in envelope.events {
                if case .taskActivity(let activity) = event {
                    self.taskActivityStore.addActivity(
                        self.scopedTaskActivity(activity)
                    )
                }
            }
        }
    }

    func syncTodoIfNeeded(
        type: String,
        payload: [String: String]
    ) {
        guard type == "todo_write"
            || payload.keys.contains(where: {
                $0.hasPrefix("todo_")
            })
        else { return }
        guard let todoStore,
              let parsedTodo = EventNormalizer.parseTodoWrite(
                  payload: payload
              )
        else { return }

        todoStore.upsertFromAgent(
            id: parsedTodo.id,
            title: parsedTodo.title,
            status: parsedTodo.status,
            priority: parsedTodo.priority,
            notes: parsedTodo.notes,
            activeForm: parsedTodo.activeForm,
            linkedFiles: parsedTodo.files,
            conversationId: conversationId
        )
    }
}
