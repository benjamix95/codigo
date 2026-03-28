import Foundation

func shouldPreferPipelineTimelineBlocks(
    localBlocks: [PersistedChatTimelineBlock],
    pipelineBlocks: [PersistedChatTimelineBlock]
) -> Bool {
    if pipelineBlocks.count > localBlocks.count { return true }

    let locMarkers = localBlocks.filter { $0.kind == .toolMarker }.count
    let pipeMarkers = pipelineBlocks.filter { $0.kind == .toolMarker }.count
    if pipeMarkers > locMarkers { return true }

    let locPrimaryCount = localBlocks.filter { $0.kind == .primaryText }.count
    let pipePrimaryCount = pipelineBlocks.filter { $0.kind == .primaryText }.count
    if pipePrimaryCount > locPrimaryCount { return true }

    let locMaxSequence = localBlocks.map(\.sequence).max() ?? 0
    let pipeMaxSequence = pipelineBlocks.map(\.sequence).max() ?? 0
    return pipeMaxSequence > locMaxSequence
}

extension ChatStore {
    /// Dopo `sync_assistant_pipeline_state` con `applied == true`, `RustMainChatStoreAdapter.apply`
    /// può lasciare il messaggio assistente in `conversations` senza i `blocks` appena committati dalla
    /// pipeline Swift (marker tool). La timeline legge `conversations` → resta monolitica finché non
    /// allineiamo esplicitamente quando la pipeline ha **più** struttura (blocchi / marker).
    @MainActor
    func applyCommittedPipelineMessageToLocalAssistant(
        convIdx: Int,
        msgIdx: Int,
        applied: Bool,
        pipelineMessage: ChatMessage
    ) {
        if !applied {
            conversations[convIdx].messages[msgIdx] = pipelineMessage
            return
        }
        let msg = conversations[convIdx].messages[msgIdx]
        if Self.pipelineLocalShouldTakeSwiftBlocks(local: msg, pipeline: pipelineMessage) {
            conversations[convIdx].messages[msgIdx] = pipelineMessage
            // #region agent log
            let locB = msg.blocks ?? []
            let pipeB = pipelineMessage.blocks ?? []
            ChatStorePipelineSyncDebug72.logPreferPipeline(
                reason: "prefer_pipeline_structure",
                msgId: pipelineMessage.id,
                locMarkers: locB.filter { $0.kind == .toolMarker }.count,
                pipeMarkers: pipeB.filter { $0.kind == .toolMarker }.count,
                locBlocks: locB.count,
                pipeBlocks: pipeB.count,
                applied: true
            )
            // #endregion
            return
        }
        let incoming = (pipelineMessage.primaryTextSnapshot ?? pipelineMessage.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = (msg.primaryTextSnapshot ?? msg.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !incoming.isEmpty, visible.isEmpty {
            conversations[convIdx].messages[msgIdx] = pipelineMessage
            // #region agent log
            ChatStorePipelineSyncDebug72.logPreferPipeline(
                reason: "visible_empty_fallback",
                msgId: pipelineMessage.id,
                locMarkers: (msg.blocks ?? []).filter { $0.kind == .toolMarker }.count,
                pipeMarkers: (pipelineMessage.blocks ?? []).filter { $0.kind == .toolMarker }.count,
                locBlocks: (msg.blocks ?? []).count,
                pipeBlocks: (pipelineMessage.blocks ?? []).count,
                applied: true
            )
            // #endregion
        }
    }

    private static func pipelineLocalShouldTakeSwiftBlocks(local: ChatMessage, pipeline: ChatMessage) -> Bool {
        let locBlocks = local.blocks ?? []
        let pipeBlocks = pipeline.blocks ?? []
        return shouldPreferPipelineTimelineBlocks(
            localBlocks: locBlocks,
            pipelineBlocks: pipeBlocks
        )
    }
}

// #region agent log
private enum ChatStorePipelineSyncDebug72 {
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-72ead1.log"
    private static let lock = NSLock()
    private static var lastAt: CFAbsoluteTime = 0

    static func logPreferPipeline(
        reason: String,
        msgId: UUID,
        locMarkers: Int,
        pipeMarkers: Int,
        locBlocks: Int,
        pipeBlocks: Int,
        applied: Bool
    ) {
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAt > 0.45 else {
            lock.unlock()
            return
        }
        lastAt = now
        lock.unlock()

        let payload: [String: Any] = [
            "sessionId": "72ead1",
            "runId": "pipeline-local-sync15",
            "hypothesisId": "H32",
            "location": "ChatStore+PipelineStateLocalSync.swift:applyCommitted",
            "message": "rust_applied_local_blocks_sync",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "reason": reason,
                "msgId": msgId.uuidString.lowercased(),
                "locMarkers": "\(locMarkers)",
                "pipeMarkers": "\(pipeMarkers)",
                "locBlocks": "\(locBlocks)",
                "pipeBlocks": "\(pipeBlocks)",
                "applied": applied ? "true" : "false",
            ],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8)
        else { return }
        line.append("\n")
        let data = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: data)
        } else if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            h.write(data)
        }
    }
}

// #endregion
