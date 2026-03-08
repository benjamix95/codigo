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

    /// Appends a text delta to the Response section without
    /// destroying other accumulated sections (Activity, Thinking, etc).
    private func appendTextDelta(id: UUID, delta: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = chatMessages[index].content
        let responseHeading = "### Response"

        if let headingRange = current.range(of: responseHeading) {
            // Find the boundary of the Response section
            let afterHeading = current[headingRange.upperBound...]
            if let nextSection = afterHeading.range(of: "\n### ") {
                // Insert delta before the next section heading
                let before = String(current[..<nextSection.lowerBound])
                let after = String(current[nextSection.lowerBound...])
                chatMessages[index].content = before + delta + after
            } else {
                // Response is the last section — safe to append
                chatMessages[index].content = current + delta
            }
        } else {
            // Create a new Response section
            var updated = current
            if !updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated += "\n\n"
            }
            updated += responseHeading + "\n" + delta
            chatMessages[index].content = updated
        }
        persistChatState()
    }

    /// Replaces only the Response section content, preserving
    /// Activity, Thinking, and other accumulated sections.
    private func replaceResponseSection(id: UUID, replacement: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = chatMessages[index].content
        let responseHeading = "### Response"

        guard current.contains(responseHeading) else {
            // No response section yet — append as new section
            appendTextDelta(id: id, delta: replacement)
            return
        }

        let separator = "\n---\n"

        // Split into logPart and verdictPart
        let parts = current.components(separatedBy: separator)
        let verdictPart = parts.count > 1
            ? parts.dropFirst().joined(separator: separator)
            : ""

        let logPart = parts.first ?? current

        // Find the response heading in the logPart and replace everything after it
        guard let logHeadingRange = logPart.range(of: responseHeading) else {
            appendTextDelta(id: id, delta: replacement)
            return
        }

        // Check if there's another ### section after the Response section
        let afterLogHeading = logPart[logHeadingRange.upperBound...]
        let nextHeadingOffset = afterLogHeading.range(of: "\n### ")

        var newLogPart: String
        if let nextRange = nextHeadingOffset {
            // Preserve sections after Response
            let beforeResponse = String(logPart[..<logHeadingRange.lowerBound])
            let afterResponse = String(afterLogHeading[nextRange.lowerBound...])
            newLogPart = beforeResponse + responseHeading + "\n"
                + replacement + afterResponse
        } else {
            // Response is the last section in logPart
            let beforeResponse = String(logPart[..<logHeadingRange.lowerBound])
            newLogPart = beforeResponse + responseHeading + "\n" + replacement
        }

        let rebuilt = verdictPart.isEmpty
            ? newLogPart.trimmingCharacters(in: .whitespacesAndNewlines)
            : newLogPart.trimmingCharacters(in: .whitespacesAndNewlines)
                + separator + verdictPart
        chatMessages[index].content = rebuilt
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
        appendReviewRunSectionLine(
            id: id,
            sectionTitle: formatted.sectionTitle,
            line: formatted.line
        )
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
