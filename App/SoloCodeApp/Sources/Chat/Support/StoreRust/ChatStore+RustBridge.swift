import Foundation
import CoderEngine

func shouldSkipRustStoreBootstrapForTests(environment: [String: String]) -> Bool { shouldDeferRustReviewCoreBootstrap(environment: environment) }

extension ChatStore {
    @MainActor
    func fallbackAppendMessage(
        _ message: ChatMessage,
        in conversationId: UUID
    ) {
        guard let index = conversationIndex(for: conversationId) else { return }
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
    func fallbackUpdateAssistantContent(
        conversationId: UUID,
        messageId: UUID? = nil,
        content: String
    ) {
        guard let conversationIndex = conversationIndex(for: conversationId) else { return }
        let targetIndex: Int? = {
            if let messageId {
                return conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageId })
            }
            return fallbackAssistantMutationIndex(in: conversations[conversationIndex])
        }()
        guard let targetIndex else { return }
        // Assign both fields in a single array mutation to avoid triggering
        // @Published objectWillChange twice. Each separate `conversations[i]`
        // write triggers COW + @Published notification → two full hierarchy
        // rebuilds for what is logically one update.
        var msg = conversations[conversationIndex].messages[targetIndex]
        msg.content = content
        msg.primaryTextSnapshot = content
        conversations[conversationIndex].messages[targetIndex] = msg
    }

    @MainActor
    func fallbackSetAssistantStreaming(
        conversationId: UUID,
        streaming: Bool
    ) {
        guard let conversationIndex = conversationIndex(for: conversationId),
              let targetIndex = fallbackAssistantMutationIndex(in: conversations[conversationIndex]) else { return }
        conversations[conversationIndex].messages[targetIndex].isStreaming = streaming
    }

    @MainActor
    func fallbackInsertMessage(
        _ message: ChatMessage,
        before messageId: UUID,
        in conversationId: UUID
    ) {
        guard let conversationIndex = conversationIndex(for: conversationId) else { return }
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
            snapshot: MainChatStoreSnapshotBridge(conversations: [], planBoards: [:]),
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

        if let scope = rustStoreActionScope(for: request) {
            request.snapshot = scopedRustStoreSnapshot(for: request, scope: scope)
            guard let snapshot = RustMainChatStoreAdapter.handle(request) else {
                return false
            }
            RustMainChatStoreAdapter.applyScopedStoreAction(
                snapshot: snapshot,
                to: self,
                scope: scope
            )
            return true
        }

        request.snapshot = normalizedRustStoreSnapshot()
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
        guard let fallbackState = Self.fallbackTaskRuntimeState(from: request) else {
            return false
        }
        RustMainChatStoreAdapter.apply(taskRuntimeState: fallbackState, to: self)
        return true
    }

    @MainActor
    func requireRustTaskRuntime(
        _ operation: String,
        configure: (inout MainChatTaskRuntimeRequestBridge) -> Void
    ) {
        guard applyRustTaskRuntimeAction(operation, configure: configure) else {
            NSLog("[ChatStore] Main chat task runtime unavailable for %@", operation)
            return
        }
    }
}
