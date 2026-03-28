import Foundation

// #region agent log
/// NDJSON sessione Cursor `72ead1` — merge timeline streaming / conversation runtime.
enum StreamingTimelineMergeDebug72 {
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-72ead1.log"
    private static let lock = NSLock()
    private static var lastAt: CFAbsoluteTime = 0
    private static var lastConvRuntimeAt: CFAbsoluteTime = 0
    private static var lastOutsideSurfaceAt: CFAbsoluteTime = 0
    private static var lastAssistantCacheAt: CFAbsoluteTime = 0
    private static var lastRustReconcileAt: CFAbsoluteTime = 0

    static func logBlocksMergedOutsideActiveSurface(
        messageId: UUID,
        pipeToolMarkers: Int
    ) {
        guard throttle(&lastOutsideSurfaceAt, minInterval: 0.45) else { return }
        appendPayload([
            "sessionId": "72ead1",
            "runId": "streaming-surface20",
            "hypothesisId": "H37",
            "location": "StreamingTimelineMergeDebug72.swift:logBlocksMergedOutsideActiveSurface",
            "message": "pipeline_blocks_merged_outside_active_streaming_surface",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "messageId": messageId.uuidString.lowercased(),
                "pipeToolMarkers": "\(pipeToolMarkers)",
            ],
        ])
    }

    /// Merge da `pipelineTurnStateByAssistantMessageId` (turno corrente della conv punta a un altro `assistantMessageId`).
    static func logMergeUsesAssistantMessagePipelineCache(
        conversationId: UUID,
        messageId: UUID,
        pipeMarkers: Int
    ) {
        guard throttle(&lastAssistantCacheAt, minInterval: 0.35) else { return }
        appendPayload([
            "sessionId": "72ead1",
            "runId": "streaming-assistant-cache21",
            "hypothesisId": "H38",
            "location": "StreamingTimelineMergeDebug72.swift:logMergeUsesAssistantMessagePipelineCache",
            "message": "merge_uses_assistant_message_pipeline_cache",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "conversationId": conversationId.uuidString.lowercased(),
                "messageId": messageId.uuidString.lowercased(),
                "pipeMarkers": "\(pipeMarkers)",
            ],
        ])
    }

    static func logMergeUsesConversationRuntime(
        conversationId: UUID,
        messageId: UUID,
        pipeMarkers: Int
    ) {
        guard throttle(&lastConvRuntimeAt, minInterval: 0.35) else { return }
        appendPayload([
            "sessionId": "72ead1",
            "runId": "streaming-conv-runtime19",
            "hypothesisId": "H36",
            "location": "StreamingTimelineMergeDebug72.swift:logMergeUsesConversationRuntime",
            "message": "merge_uses_conversation_runtime_not_integration",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "conversationId": conversationId.uuidString.lowercased(),
                "messageId": messageId.uuidString.lowercased(),
                "pipeMarkers": "\(pipeMarkers)",
            ],
        ])
    }

    /// Timeline Swift con `.toolUse` ripristinata dopo che Rust ha restituito `timelineSegments` vuoti.
    static func logRustTimelineReconciled(
        messageId: UUID,
        preservedToolSegments: Int
    ) {
        guard throttle(&lastRustReconcileAt, minInterval: 0.4) else { return }
        appendPayload([
            "sessionId": "72ead1",
            "runId": "rust-timeline-reconcile22",
            "hypothesisId": "H39",
            "location": "StreamingTimelineMergeDebug72.swift:logRustTimelineReconciled",
            "message": "rust_empty_timeline_reused_swift_tool_segments",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "messageId": messageId.uuidString.lowercased(),
                "preservedToolSegments": "\(preservedToolSegments)",
            ],
        ])
    }

    static func logStructureWithoutPayloadDelta(
        baseToolMarkers: Int,
        pipeToolMarkers: Int,
        storePayload: Int,
        pipelinePayload: Int
    ) {
        guard throttle(&lastAt, minInterval: 0.5) else { return }
        appendPayload([
            "sessionId": "72ead1",
            "runId": "streaming-structure16",
            "hypothesisId": "H33",
            "location": "StreamingTimelineMergeDebug72.swift:logStructureWithoutPayloadDelta",
            "message": "pipeline_structure_merge_without_payload_delta",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": [
                "baseToolMarkers": "\(baseToolMarkers)",
                "pipeToolMarkers": "\(pipeToolMarkers)",
                "storePayload": "\(storePayload)",
                "pipelinePayload": "\(pipelinePayload)",
            ],
        ])
    }

    private static func throttle(_ last: inout CFAbsoluteTime, minInterval: CFAbsoluteTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - last >= minInterval else { return false }
        last = now
        return true
    }

    private static func appendPayload(_ payload: [String: Any]) {
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
