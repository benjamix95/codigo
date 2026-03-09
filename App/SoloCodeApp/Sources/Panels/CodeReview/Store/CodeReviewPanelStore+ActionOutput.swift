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
    /// Uses `responseMessageIds` dictionary to track the stable
    /// mapping between activity and response message IDs.
    private func responseMessageIndex(
        for activityId: UUID
    ) -> Int {
        // Check if we already have a response message for this activity
        if let responseId = responseMessageIds[activityId],
           let index = chatMessages.firstIndex(where: { $0.id == responseId })
        {
            return index
        }

        // Create a new response message right after the activity message
        let responseId = UUID()
        let responseMessage = ReviewPanelMessage(
            id: responseId,
            role: .assistant,
            kind: .plain,
            content: "",
            isStreaming: true
        )
        responseMessageIds[activityId] = responseId

        if let activityIndex = chatMessages.firstIndex(
            where: { $0.id == activityId }
        ) {
            chatMessages.insert(responseMessage, at: activityIndex + 1)
            return activityIndex + 1
        } else {
            chatMessages.append(responseMessage)
            return chatMessages.count - 1
        }
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
        finalizeResponseMessage(for: id)
        persistChatState()
    }

    func failPanelActionOutput(id: UUID, error: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = "Error: \(error)"
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        finalizeResponseMessage(for: id)
        persistChatState()
    }

    /// Stops streaming on the separate response message, if one exists.
    /// If the response contains a verdict separator (`\n---\n`),
    /// splits off the verdict into its own summary message.
    private func finalizeResponseMessage(for activityId: UUID) {
        guard let responseId = responseMessageIds.removeValue(forKey: activityId),
              let index = chatMessages.firstIndex(where: { $0.id == responseId })
        else { return }
        chatMessages[index].isStreaming = false

        let content = chatMessages[index].content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove empty response messages (no textDelta was ever received)
        if content.isEmpty {
            chatMessages.remove(at: index)
            return
        }

        // Split verdict from response if a --- separator exists
        let separator = "\n---\n"
        if let separatorRange = content.range(of: separator) {
            let responsePart = String(content[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let verdictPart = String(content[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            chatMessages[index].content = responsePart

            // Remove response if empty after split
            if responsePart.isEmpty {
                chatMessages.remove(at: index)
            }

            // Add verdict as a separate summary-style message
            if !verdictPart.isEmpty {
                let verdictMessage = ReviewPanelMessage(
                    role: .assistant,
                    kind: .reviewRun,
                    content: verdictPart
                )
                let insertAt = chatMessages.firstIndex(
                    where: { $0.id == responseId }
                ).map { $0 + 1 } ?? chatMessages.endIndex
                chatMessages.insert(verdictMessage, at: insertAt)
                // Finalize immediately to bake verdict sections
                let verdictIdx = chatMessages.firstIndex(
                    where: { $0.id == verdictMessage.id }
                )!
                ReviewPanelChatMessageFactory.finalizeReviewRunMessage(
                    &chatMessages[verdictIdx]
                )
            }
        }
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if formatted.sectionTitle == "Response" {
                // assistant_update output is cumulative — replace, don't append
                self.replaceResponseSection(id: id, replacement: formatted.line)
            } else {
                self.appendReviewRunSectionLine(
                    id: id,
                    sectionTitle: formatted.sectionTitle,
                    line: formatted.line
                )
            }
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
        DispatchQueue.main.async { [weak self] in
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
