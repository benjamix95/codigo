import Foundation
import CoderEngine

func shouldSkipRustStoreBootstrapForTests(environment: [String: String]) -> Bool { shouldDeferRustReviewCoreBootstrap(environment: environment) }

extension ChatStore {
    @MainActor
    func fallbackAppendMessage(
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
    func fallbackUpdateAssistantContent(
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
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              let targetIndex = fallbackAssistantMutationIndex(in: conversations[conversationIndex]) else { return }
        conversations[conversationIndex].messages[targetIndex].isStreaming = streaming
    }

    @MainActor
    func fallbackInsertMessage(
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

    nonisolated private static var isRustMarkersRuntimeAvailable: Bool { ReviewCoreBridge.isEnabled }

    nonisolated static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
        let core: String
        if isRustMarkersRuntimeAvailable {
            let request = MainChatMarkersRequestBridge(schemaVersion: 1, operation: "strip_coderide_markers", text: content, aggressive: aggressive)
            core = RustMainChatStoreAdapter.handleMarkers(request) ?? swiftFallbackStripCoderideMarkers(content, aggressive: aggressive)
        } else {
            core = swiftFallbackStripCoderideMarkers(content, aggressive: aggressive)
        }
        let filtered = CoderideDisplayLineFilter.stripDisplayLinesWithCoderideToolPrefix(core)
        if aggressive {
            return filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return filtered
    }

    /// Reasoning / thinking: sempre senza marker operativi `[CODERIDE:…]` in UI e persistenza.
    nonisolated static func sanitizedChatReasoningText(_ text: String) -> String {
        stripCoderideMarkers(text, aggressive: true)
    }

    /// Dettaglio sotto "Thinking…" (riga singola): strip + troncamento; `nil` se il testo è vuoto dopo strip.
    nonisolated static func sanitizedStreamingDetailLine(_ raw: String, ellipsis: String = "...") -> String? {
        let s = stripCoderideMarkers(raw, aggressive: true).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.count > 80 {
            return String(s.prefix(77)) + ellipsis
        }
        return s
    }

    nonisolated private static func swiftFallbackStripCoderideMarkers(_ content: String, aggressive: Bool) -> String {
        var working = content
        let pattern = "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]"
        working = working.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        // Marker senza `]` (streaming/troncato): rimuovi dalla `[` fino a fine riga o fine stringa.
        while let range = working.range(of: "[CODERIDE", options: .caseInsensitive) {
            let tail = working[range.lowerBound...]
            if let close = tail.firstIndex(of: "]") {
                working.removeSubrange(range.lowerBound...close)
            } else if let nl = tail.firstIndex(of: "\n") {
                working.removeSubrange(range.lowerBound..<nl)
            } else {
                working.removeSubrange(range.lowerBound..<working.endIndex)
                break
            }
        }
        let stripped = working.trimmingCharacters(in: .whitespacesAndNewlines)
        if aggressive {
            return stripped
        }
        return stripped
    }

    nonisolated static func extractLastOperationalThinkingLine(from content: String) -> String? {
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
