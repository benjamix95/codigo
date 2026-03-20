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
}
