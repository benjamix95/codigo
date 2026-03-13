import CoderEngine
import Foundation

enum ReviewPanelActionOutputRuntime {
    case run
    case chat

    var reduceFunctionName: String {
        switch self {
        case .run: return "review_core_panel_run_reduce_event"
        case .chat: return "review_core_panel_chat_reduce_event"
        }
    }
}

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
        finishedReviewRunActivityIds.remove(assistantId)
        appendChatMessage(
            ReviewPanelMessage(
                id: assistantId,
                role: .assistant,
                kind: .reviewRun,
                content: "",
                isStreaming: true
            )
        )
        return assistantId
    }

    func streamPanelActionOutput(
        id: UUID,
        event: StreamEvent,
        runtime: ReviewPanelActionOutputRuntime = .run
    ) {
        if case .raw(let type, let payload) = event {
            ingestRawReviewActivity(type: type, payload: payload)
            syncTodoIfNeeded(type: type, payload: payload)
        }
        let response: ReviewPanelRuntimeResponse? = ReviewCoreBridge.call(
            functionName: runtime.reduceFunctionName,
            request: ReviewPanelOutputEventRequest(
                state: makeRuntimeStateSnapshot(),
                activityMessageId: id.uuidString,
                suggestedResponseMessageId: UUID().uuidString,
                suggestedVerdictMessageId: UUID().uuidString,
                timestamp: Date(),
                event: ReviewPanelRuntimeEventEnvelope(event)
            )
        )
        guard response?.error == nil, let state = response?.state else {
            appendPanelSystemMessage(
                ReviewPanelStateRustAdapter.runtimeUnavailableMessage,
                kind: .statusNote,
                selectChatTab: true
            )
            return
        }
        applyRuntimeState(state)
    }

    func handleRawReviewRunEvent(
        id: UUID,
        type: String,
        payload: [String: String]
    ) {
        streamPanelActionOutput(
            id: id,
            event: .raw(type: type, payload: payload),
            runtime: .run
        )
    }

    @discardableResult
    func finishPanelActionOutput(
        id: UUID,
        runtime: ReviewPanelActionOutputRuntime = .run,
        fallbackContent: String? = nil
    ) -> ReviewPanelRuntimeOutcome? {
        _ = runtime
        return applyPanelChatFinish(
            assistantId: id,
            fallbackContent: fallbackContent,
            error: nil,
            wasCancelled: false,
            finishAllStreaming: false
        )
    }

    @discardableResult
    func failPanelActionOutput(
        id: UUID,
        error: String,
        runtime: ReviewPanelActionOutputRuntime = .run,
        wasCancelled: Bool = false
    ) -> ReviewPanelRuntimeOutcome? {
        _ = runtime
        return applyPanelChatFinish(
            assistantId: wasCancelled ? nil : id,
            fallbackContent: nil,
            error: wasCancelled ? nil : error,
            wasCancelled: wasCancelled,
            finishAllStreaming: wasCancelled
        )
    }

    func ingestRawReviewActivity(
        type: String,
        payload: [String: String]
    ) {
        let enrichedPayload = enrichedReviewRawPayload(type: type, payload: payload)
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: effectivePanelProviderId ?? "review-panel",
            type: type,
            payload: enrichedPayload
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.taskActivityStore.scheduleAddEnvelope(envelope)
            for event in envelope.events {
                if case .taskActivity(let activity) = event {
                    self.taskActivityStore.scheduleAddActivity(
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
        guard type == "todo_write" || payload.keys.contains(where: { $0.hasPrefix("todo_") }) else {
            return
        }
        guard let todoStore,
              let parsedTodo = EventNormalizer.parseTodoWrite(payload: payload) else {
            return
        }
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

private struct ReviewPanelOutputEventRequest: Encodable {
    let schemaVersion: Int = 1
    let state: ReviewPanelRuntimeStateSnapshot
    let activityMessageId: String
    let suggestedResponseMessageId: String
    let suggestedVerdictMessageId: String
    let timestamp: Date
    let event: ReviewPanelRuntimeEventEnvelope
}

private extension ReviewPanelRuntimeEventEnvelope {
    init(_ event: StreamEvent) {
        switch event {
        case .started:
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "started",
                text: nil,
                eventType: nil,
                payload: [:]
            )
        case .completed:
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "completed",
                text: nil,
                eventType: nil,
                payload: [:]
            )
        case .textDelta(let delta):
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "textDelta",
                text: delta,
                eventType: nil,
                payload: [:]
            )
        case .textReplace(let replacement):
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "textReplace",
                text: replacement,
                eventType: nil,
                payload: [:]
            )
        case .error(let message):
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "error",
                text: message,
                eventType: nil,
                payload: [:]
            )
        case .raw(let type, let payload):
            self = ReviewPanelRuntimeEventEnvelope(
                kind: "raw",
                text: nil,
                eventType: type,
                payload: payload
            )
        }
    }
}
