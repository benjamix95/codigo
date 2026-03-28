import Foundation

extension ChatTurnState {
    /// Rust `pipeline_apply_event` può restituire `timelineSegments` **vuoti** pur aggiornando testo/metadata:
    /// Swift ha già inserito `.toolUse` via `toolTraceArtifact`, poi un `textDelta` rimpiazza lo stato senza timeline →
    /// `blocks` senza `toolMarker` ma trace in UI → log **H26**.
    func reconcilingTimelineWhenRustReturnedEmptyWhileSwiftHadToolMarkers(
        previous: ChatTurnState
    ) -> ChatTurnState {
        guard assistantMessageId == previous.assistantMessageId,
              conversationId == previous.conversationId,
              timelineSegments.isEmpty,
              previous.timelineSegments.contains(where: { $0.kind == .toolUse })
        else { return self }

        var merged = self
        merged.timelineSegments = previous.timelineSegments
        merged.timelineNextSequence = max(previous.timelineNextSequence, timelineNextSequence)
        if textSegments.isEmpty, !previous.textSegments.isEmpty {
            merged.textSegments = previous.textSegments
        } else if textSegments.count == previous.textSegments.count {
            merged.textSegments = textSegments
        }
        return merged
    }
}
