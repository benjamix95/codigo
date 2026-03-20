import Foundation

extension ChatStore {
    @MainActor
    func normalizedRustStoreSnapshot() -> MainChatStoreSnapshotBridge {
        let local = RustMainChatStoreAdapter.snapshot(from: self)
        return RustMainChatStoreAdapter.loadNormalizedSnapshot(local) ?? local
    }

    @MainActor
    func normalizeLoadedRustStoreSnapshot() {
        let local = RustMainChatStoreAdapter.snapshot(from: self)
        if let normalized = RustMainChatStoreAdapter.loadNormalizedSnapshot(local) {
            RustMainChatStoreAdapter.apply(snapshot: normalized, to: self)
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
            stringList: []
        )
        configure(&request)
        guard let snapshot = RustMainChatStoreAdapter.handle(request) else {
            return false
        }
        RustMainChatStoreAdapter.apply(snapshot: snapshot, to: self)
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
        guard let state = RustMainChatStoreAdapter.handleTaskRuntime(request) else {
            return false
        }
        RustMainChatStoreAdapter.apply(taskRuntimeState: state, to: self)
        return true
    }

    @MainActor
    private func requireRustTaskRuntime(
        _ operation: String,
        configure: (inout MainChatTaskRuntimeRequestBridge) -> Void
    ) {
        guard applyRustTaskRuntimeAction(operation, configure: configure) else {
            assertionFailure("Main chat task runtime unavailable for \(operation)")
            return
        }
    }

    @MainActor
    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let conversationId else { return }
        _ = applyRustStoreAction("set_streaming_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = streaming
        }
        if !streaming {
            saveConversationsImmediately()
        } else {
            saveConversations()
        }
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
}
