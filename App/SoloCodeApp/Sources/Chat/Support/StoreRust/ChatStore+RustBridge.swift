import Foundation
import CoderEngine

func shouldSkipRustStoreBootstrapForTests(environment: [String: String]) -> Bool { shouldDeferRustReviewCoreBootstrap(environment: environment) }

extension ChatStore {
    @MainActor
    private func fallbackAppendMessage(
        _ message: ChatMessage,
        in conversationId: UUID
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if conversations[index].messages.contains(where: { $0.id == message.id }) {
            return
        }
        conversations[index].messages.append(message)
        let trimmedTitle = conversations[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.role == .user,
           !fallbackTitle.isEmpty,
           (trimmedTitle.isEmpty || trimmedTitle == "New conversation") {
            conversations[index].title = fallbackTitle
        }
    }

    @MainActor
    private func fallbackUpdateAssistantContent(
        conversationId: UUID,
        messageId: UUID? = nil,
        content: String
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let targetIndex: Int? = {
            if let messageId {
                return conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageId })
            }
            return fallbackAssistantMutationIndex(in: conversations[conversationIndex])
        }()
        guard let targetIndex else { return }
        conversations[conversationIndex].messages[targetIndex].content = content
        conversations[conversationIndex].messages[targetIndex].primaryTextSnapshot = content
    }

    @MainActor
    private func fallbackSetAssistantStreaming(
        conversationId: UUID,
        streaming: Bool
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              let targetIndex = fallbackAssistantMutationIndex(in: conversations[conversationIndex]) else { return }
        conversations[conversationIndex].messages[targetIndex].isStreaming = streaming
    }

    @MainActor
    private func fallbackInsertMessage(
        _ message: ChatMessage,
        before messageId: UUID,
        in conversationId: UUID
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if conversations[conversationIndex].messages.contains(where: { $0.id == message.id }) {
            return
        }
        let anchorIndex = conversations[conversationIndex].messages.firstIndex { $0.id == messageId }
        if let anchorIndex {
            conversations[conversationIndex].messages.insert(message, at: anchorIndex)
        } else {
            conversations[conversationIndex].messages.append(message)
        }
    }

    private static func fallbackTaskRuntimeState(
        from request: MainChatTaskRuntimeRequestBridge
    ) -> MainChatTaskRuntimeStateBridge? {
        guard request.schemaVersion == 1 else { return nil }

        var states = request.state.taskStates

        func taskIndex(_ conversationId: String) -> Int? {
            states.firstIndex { $0.conversationId == conversationId }
        }

        switch request.operation {
        case "begin_task":
            guard let conversationId = request.conversationId else { return nil }
            if let index = taskIndex(conversationId) {
                let current = states[index]
                states[index] = MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId,
                    startedAt: request.startedAt ?? current.startedAt,
                    statusText: "Thinking"
                )
            } else {
                states.append(
                    MainChatTaskStateSnapshotBridge(
                        conversationId: conversationId,
                        startedAt: request.startedAt,
                        statusText: "Thinking"
                    )
                )
            }
        case "end_task":
            guard let conversationId = request.conversationId else { return nil }
            states.removeAll { $0.conversationId == conversationId }
        case "set_task_status":
            guard let conversationId = request.conversationId,
                  let statusText = request.statusText else { return nil }
            if let index = taskIndex(conversationId) {
                let current = states[index]
                states[index] = MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId,
                    startedAt: current.startedAt,
                    statusText: statusText
                )
            }
        default:
            return nil
        }

        states.sort {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
                || (($0.startedAt == $1.startedAt) && $0.conversationId < $1.conversationId)
        }
        return MainChatTaskRuntimeStateBridge(taskStates: states)
    }

    private static var isRustMarkersRuntimeAvailable: Bool { ReviewCoreBridge.isEnabled }

    static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
        guard isRustMarkersRuntimeAvailable else { return aggressive ? content.trimmingCharacters(in: .whitespacesAndNewlines) : content }
        let request = MainChatMarkersRequestBridge(schemaVersion: 1, operation: "strip_coderide_markers", text: content, aggressive: aggressive)
        guard let result = RustMainChatStoreAdapter.handleMarkers(request) else { return aggressive ? content.trimmingCharacters(in: .whitespacesAndNewlines) : content }
        return result
    }

    static func extractLastOperationalThinkingLine(from content: String) -> String? {
        guard isRustMarkersRuntimeAvailable else { return nil }
        let request = MainChatMarkersRequestBridge(schemaVersion: 1, operation: "extract_last_operational_thinking_line", text: content, aggressive: nil)
        guard let result = RustMainChatStoreAdapter.handleMarkers(request) else { return nil }
        return result.isEmpty ? nil : result
    }

    @MainActor
    func normalizedRustStoreSnapshot() -> MainChatStoreSnapshotBridge {
        let local = RustMainChatStoreAdapter.snapshot(from: self)
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
            return local
        }
        return RustMainChatStoreAdapter.loadNormalizedSnapshot(local) ?? local
    }

    @MainActor
    func normalizeLoadedRustStoreSnapshot() {
        guard ReviewCoreBridge.isEnabled else { return }
        let local = RustMainChatStoreAdapter.snapshot(from: self)
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
            return
        }
        if let normalized = RustMainChatStoreAdapter.loadNormalizedSnapshot(local) {
            RustMainChatStoreAdapter.apply(
                snapshot: normalized,
                to: self,
                preserveLocalMessages: false
            )
        }
    }

    @MainActor
    @discardableResult
    func applyRustStoreAction(
        _ action: String,
        configure: (inout MainChatStoreActionRequestBridge) -> Void
    ) -> Bool {
        var request = MainChatStoreActionRequestBridge(
            schemaVersion: 1,
            action: action,
            snapshot: normalizedRustStoreSnapshot(),
            conversationId: nil,
            messageId: nil,
            checkpointId: nil,
            messageCount: nil,
            conversation: nil,
            message: nil,
            planBoard: nil,
            checkpoint: nil,
            title: nil,
            mode: nil,
            providerId: nil,
            contextId: nil,
            contextFolderPath: nil,
            workspaceId: nil,
            boolValue: nil,
            intValue: nil,
            text: nil,
            stringList: [],
            subagentCards: nil
        )
        configure(&request)
        guard let snapshot = RustMainChatStoreAdapter.handle(request) else {
            return false
        }
        RustMainChatStoreAdapter.apply(
            snapshot: snapshot,
            to: self,
            preserveLocalMessages: false
        )
        return true
    }

    @MainActor
    @discardableResult
    func applyRustTaskRuntimeAction(
        _ operation: String,
        configure: (inout MainChatTaskRuntimeRequestBridge) -> Void
    ) -> Bool {
        var request = MainChatTaskRuntimeRequestBridge(
            schemaVersion: 1,
            operation: operation,
            state: RustMainChatStoreAdapter.taskRuntimeState(from: self),
            conversationId: nil,
            statusText: nil,
            startedAt: nil
        )
        configure(&request)
        if let state = RustMainChatStoreAdapter.handleTaskRuntime(request) {
            RustMainChatStoreAdapter.apply(taskRuntimeState: state, to: self)
            return true
        }
        guard shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) else {
            return false
        }
        guard let fallbackState = Self.fallbackTaskRuntimeState(from: request) else {
            return false
        }
        RustMainChatStoreAdapter.apply(taskRuntimeState: fallbackState, to: self)
        return true
    }

    @MainActor
    private func requireRustTaskRuntime(
        _ operation: String,
        configure: (inout MainChatTaskRuntimeRequestBridge) -> Void
    ) {
        guard applyRustTaskRuntimeAction(operation, configure: configure) else {
            NSLog("[ChatStore] Main chat task runtime unavailable for %@", operation)
            return
        }
    }

    @MainActor
    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let conversationId else { return }
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("set_streaming_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = streaming
        }
        if !applied, allowLocalFallback {
            fallbackSetAssistantStreaming(conversationId: conversationId, streaming: streaming)
        }
        if !streaming {
            saveConversationsImmediately()
        } else {
            saveConversations()
        }
    }

    @MainActor
    func addMessage(_ message: ChatMessage, to conversationId: UUID?) {
        guard let conversationId else { return }
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("append_message") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied, allowLocalFallback {
            fallbackAppendMessage(message, in: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied, allowLocalFallback {
            fallbackUpdateAssistantContent(conversationId: conversationId, content: resolvedContent)
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    func updateAssistantMessage(
        messageId: UUID,
        content: String,
        in conversationId: UUID?,
        persistImmediately: Bool = true
    ) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied, allowLocalFallback {
            fallbackUpdateAssistantContent(
                conversationId: conversationId,
                messageId: messageId,
                content: resolvedContent
            )
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    func insertMessage(_ message: ChatMessage, before messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("insert_message_before") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied, allowLocalFallback {
            fallbackInsertMessage(message, before: messageId, in: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func removeTrailingEmptyAssistantMessages(in conversationId: UUID?) {
        guard let conversationId else { return }
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment),
           let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) {
            while let last = conversations[conversationIndex].messages.last,
                  last.role == .assistant,
                  !last.isStreaming,
                  last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversations[conversationIndex].messages.removeLast()
            }
        } else {
            _ = applyRustStoreAction("remove_trailing_empty_assistant_messages") { request in
                request.conversationId = conversationId.uuidString.lowercased()
            }
        }
        saveConversationsImmediately()
    }

    @MainActor
    private func fallbackAssistantMutationIndex(in conversation: Conversation) -> Int? {
        if let streamingIndex = conversation.messages.lastIndex(where: {
            $0.role == .assistant && $0.isStreaming
        }) {
            return streamingIndex
        }
        return conversation.messages.lastIndex(where: { $0.role == .assistant })
    }

    @MainActor
    func saveSubagentCardsToLastAssistant(_ cards: [SubagentCardSnapshot], in conversationId: UUID?) {
        guard !cards.isEmpty, let conversationId else { return }
        let applied = applyRustStoreAction("save_subagent_cards_to_last_assistant") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.subagentCards = cards.map(RustMainChatStoreAdapter.subagentCardSnapshot)
        }
        if !applied {
            NSLog("[ChatStore] save_subagent_cards_to_last_assistant failed for conv=%@", conversationId.uuidString)
        }
        saveConversationsImmediately()
    }

    @MainActor
    func saveReasoningToLastAssistant(reasoning: String, in conversationId: UUID?) {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversationId else { return }
        let applied = applyRustStoreAction("save_reasoning") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = trimmed
        }
        if !applied {
            NSLog("[ChatStore] save_reasoning failed for conv=%@", conversationId.uuidString)
        }
        saveConversations()
    }

    @MainActor
    func removeAssistantMessageIfEmpty(messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("remove_assistant_message_if_empty") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
        }
        if !applied {
            NSLog("[ChatStore] remove_assistant_message_if_empty failed for conv=%@ msg=%@", conversationId.uuidString, messageId.uuidString)
        }
        saveConversations()
    }

    @MainActor
    func removeMessage(messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("remove_message") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
        }
        if !applied {
            NSLog("[ChatStore] remove_message failed for conv=%@ msg=%@", conversationId.uuidString, messageId.uuidString)
        }
        saveConversations()
    }

    @MainActor
    func beginTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("begin_task") { request in
            request.conversationId = id.uuidString.lowercased()
            request.startedAt = Date()
        }
    }

    @MainActor
    func beginTask() {
        beginTask(conversationId: activeTaskConversationId)
    }

    @MainActor
    func endTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("end_task") { request in
            request.conversationId = id.uuidString.lowercased()
        }
    }

    @MainActor
    func setTaskStatus(_ text: String, for conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("set_task_status") { request in
            request.conversationId = id.uuidString.lowercased()
            request.statusText = text
        }
    }

    @MainActor
    func endTask() {
        endTask(conversationId: activeTaskConversationId)
    }

    @MainActor
    func updateAssistantMessagePipelineState(
        messageId: UUID,
        state: ChatTurnState,
        in conversationId: UUID,
        persistImmediately: Bool
    ) {
        if mainChatTraceLoggingEnabled() {
            NSLog(
                "[MainChatTrace] store sync_assistant_pipeline_state conv=%@ msg=%@ primary=%ld blocks=%ld streaming=%@",
                conversationId.uuidString.lowercased(),
                messageId.uuidString.lowercased(),
                state.primaryTextSnapshot.count,
                state.blocks.count,
                state.isStreaming ? "true" : "false"
            )
        }
        var pipelineMessage = ChatMessage(
            id: messageId,
            role: .assistant,
            content: state.primaryTextSnapshot,
            primaryTextSnapshot: state.primaryTextSnapshot,
            blocks: state.blocks,
            turnMetadata: state.metadata,
            isStreaming: state.isStreaming
        )
        pipelineMessage.reasoningText = state.reasoningTextSnapshot
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("sync_assistant_pipeline_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(pipelineMessage)
        }
        if mainChatTraceLoggingEnabled() {
            NSLog(
                "[MainChatTrace] store sync_assistant_pipeline_state applied=%@ conv=%@ msg=%@",
                applied ? "true" : "false",
                conversationId.uuidString.lowercased(),
                messageId.uuidString.lowercased()
            )
        }
        if !applied, allowLocalFallback,
           let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
           let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[convIdx].messages[msgIdx] = pipelineMessage
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    private func persistAssistantMutation(immediately: Bool) {
        if immediately {
            saveConversations()
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastStreamingSaveAt) >= 3.0 {
            lastStreamingSaveAt = now
            saveConversations()
        }
    }
}
