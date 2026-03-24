import Foundation

func fallbackStreamingAssistantMessageId(in conversation: Conversation?) -> UUID? {
    conversation?.messages.last(where: {
        $0.role == .assistant && $0.isStreaming
    })?.id
}

func resolvePipelineBindingTarget(
    conversation: Conversation?,
    activeTurn: ToolTraceTurnContext?
) -> (messageId: UUID, turnId: String)? {
    guard let conversation else { return nil }

    if let activeTurn {
        guard let boundMessage = conversation.messages.first(where: { $0.id == activeTurn.assistantMessageId }) else {
            return nil
        }
        let turnId = boundMessage.turnMetadata?.turnId ?? boundMessage.id.uuidString
        return (boundMessage.id, turnId)
    }

    guard let streamingMessageId = fallbackStreamingAssistantMessageId(in: conversation),
          let streamingMessage = conversation.messages.first(where: { $0.id == streamingMessageId }) else {
        return nil
    }
    let turnId = streamingMessage.turnMetadata?.turnId ?? streamingMessage.id.uuidString
    return (streamingMessage.id, turnId)
}

extension ChatPanelView {
    @MainActor
    internal func currentAssistantPipelineTarget(for conversationId: UUID?) -> (messageId: UUID, turnId: String)? {
        guard let conversationId,
              let conversation = chatStore.conversation(for: conversationId)
        else {
            return nil
        }
        let activeTurn = toolRuntime.activeToolTraceTurnsByConversation[conversationId]
        return resolvePipelineBindingTarget(
            conversation: conversation,
            activeTurn: activeTurn
        )
    }

    @MainActor
    internal func applyChatPipelineEvent(
        _ event: ChatPipelineEvent,
        persistImmediately: Bool = false
    ) {
        let currentState = conversationRuntime.activeTurnStateByConversation[event.conversationId]
            ?? restoreChatTurnState(for: event)
        let nextSequence = max(
            conversationRuntime.pipelineEventSequenceByConversation[event.conversationId, default: 0] + 1,
            event.sequence
        )
        conversationRuntime.pipelineEventSequenceByConversation[event.conversationId] = nextSequence

        let sequenced = ChatPipelineEvent(
            conversationId: event.conversationId,
            assistantMessageId: event.assistantMessageId,
            turnId: event.turnId,
            sequence: nextSequence,
            source: event.source,
            kind: event.kind,
            payload: event.payload,
            timestamp: event.timestamp
        )
        if let nextState = applyPipelineEventThroughRustBoundary(
            sequenced,
            currentState: currentState,
            persistImmediately: persistImmediately
        ) {
            conversationRuntime.activeTurnStateByConversation[event.conversationId] = nextState
            conversationRuntime.renderSnapshotByConversation[event.conversationId] = nextState
        } else if shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        ) {
            let state = ChatPipelineReducer.apply(
                state: currentState,
                event: sequenced
            )
            conversationRuntime.activeTurnStateByConversation[event.conversationId] = state
            conversationRuntime.renderSnapshotByConversation[event.conversationId] = state
            ChatPipelineCommitter.commit(
                state,
                chatStore: chatStore,
                persistImmediately: persistImmediately
            )
        } else {
            NSLog(
                "[ChatPipeline] Rust pipeline boundary unavailable for %@",
                sequenced.kind.rawValue
            )
            return
        }
        streaming.streamContentVersion &+= 1
    }

    @MainActor
    internal func applyChatPipelineEvents(
        _ events: [ChatPipelineEvent],
        persistImmediately: Bool = false
    ) {
        for event in events {
            applyChatPipelineEvent(event, persistImmediately: persistImmediately)
        }
    }

    @MainActor
    internal func applyLegacyStreamSnapshot(
        content: String,
        conversationId: UUID?,
        providerId: String
    ) {
        guard let target = currentAssistantPipelineTarget(for: conversationId),
              let conversationId else {
            return
        }
        let event = LegacyLLMStreamAdapter.textReplaceEvent(
            content: content,
            conversationId: conversationId,
            assistantMessageId: target.messageId,
            turnId: target.turnId,
            sequence: 0,
            providerId: providerId
        )
        applyChatPipelineEvent(event)
    }

    @MainActor
    internal func applyLegacyLifecycleEvent(
        kind: ChatPipelineEventKind,
        conversationId: UUID?,
        providerId: String,
        status: String,
        detail: String? = nil,
        persistImmediately: Bool = false
    ) {
        guard let target = currentAssistantPipelineTarget(for: conversationId),
              let conversationId else {
            return
        }
        let event = LegacyLLMStreamAdapter.lifecycleEvent(
            kind: kind,
            conversationId: conversationId,
            assistantMessageId: target.messageId,
            turnId: target.turnId,
            sequence: 0,
            providerId: providerId,
            status: status,
            detail: detail
        )
        applyChatPipelineEvent(event, persistImmediately: persistImmediately)
    }

    @MainActor
    internal func restoreChatTurnState(for event: ChatPipelineEvent) -> ChatTurnState {
        let message = chatStore.conversation(for: event.conversationId)?
            .messages
            .first(where: { $0.id == event.assistantMessageId })
        var state = ChatTurnState(
            conversationId: event.conversationId,
            assistantMessageId: event.assistantMessageId,
            turnId: event.turnId,
            providerId: event.payload["provider_id"] ?? event.source
        )
        state.status = message?.turnMetadata?.status ?? "idle"
        state.isStreaming = message?.isStreaming ?? false
        state.startedAt = message?.turnMetadata?.startedAt
        state.completedAt = message?.turnMetadata?.completedAt
        state.updatedAt = message?.turnMetadata?.updatedAt
        state.sequence = message?.turnMetadata?.sequence ?? 0
        state.orderedTextStreamIds = ["main"]
        if let message {
            state.textByStreamId["main"] = message.resolvedPrimaryText
            if let reasoning = message.reasoningText, !reasoning.isEmpty {
                state.reasoningByGroupId["reasoning"] = reasoning
            }
            state.artifacts = message.resolvedTimelineBlocks.compactMap { block in
                switch block.kind {
                case .primaryText, .reasoning:
                    return nil
                case .mermaid:
                    return ChatArtifact(id: block.id, kind: .mermaid, title: block.title ?? "Diagram", text: block.text)
                case .commands:
                    return ChatArtifact(id: block.id, kind: .commands, title: block.title ?? "Commands executed", items: block.items, isCollapsedByDefault: true)
                case .files:
                    return ChatArtifact(id: block.id, kind: .files, title: block.title ?? "Files touched", items: block.items, isCollapsedByDefault: true)
                case .status:
                    return ChatArtifact(id: block.id, kind: .status, title: block.title ?? "Status", text: block.text)
                case .plan:
                    return ChatArtifact(id: block.id, kind: .plan, title: block.title ?? "Plan", text: block.text)
                case .toolTrace:
                    return ChatArtifact(id: block.id, kind: .toolTrace, title: block.title ?? "Trace summary", text: block.text, isCollapsedByDefault: true)
                case .toolMarker:
                    return nil
                }
            }
        }
        return state
    }

    @MainActor
    private func applyPipelineEventThroughRustBoundary(
        _ event: ChatPipelineEvent,
        currentState: ChatTurnState,
        persistImmediately: Bool
    ) -> ChatTurnState? {
        let runtimeSnapshot = MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(currentState),
            mode: .agent,
            directStream: nil,
            plan: nil,
            output: nil
        )
        guard let response = RustMainChatStoreAdapter.applyPipelineEvent(
            event,
            to: chatStore,
            context: currentMainChatUIBridgeContext(
                conversationId: event.conversationId,
                runtimeSnapshot: runtimeSnapshot,
                includeAutoTodoRuntimeState: true
            ),
            preserveLocalMessages: false
        ), let nextState = response.state?.runtimeSnapshot?.turnState.chatTurnState else {
            return nil
        }
        if persistImmediately {
            chatStore.saveConversationsImmediately()
        } else {
            chatStore.saveConversations()
        }
        return nextState
    }
}
