import Foundation

enum ChatTurnTimelineSubagentOrdering {
    static func moveTrailingSubagentSegmentsBeforeFinalText(
        _ segments: [ChatTurnInterleavedSegment]
    ) -> [ChatTurnInterleavedSegment] {
        guard let lastTextIndex = segments.lastIndex(where: isNarrativeTextSegment) else {
            return segments
        }

        let trailingSubagentIndices = segments.indices.filter { index in
            index > lastTextIndex && isSubagentSegment(segments[index])
        }
        guard !trailingSubagentIndices.isEmpty else { return segments }

        let trailingSubagents = trailingSubagentIndices.map { segments[$0] }
        let retained = segments.enumerated().compactMap { index, segment in
            trailingSubagentIndices.contains(index) ? nil : segment
        }
        guard let insertionIndex = retained.lastIndex(where: isNarrativeTextSegment) else {
            return segments
        }

        var reordered = retained
        reordered.insert(contentsOf: trailingSubagents, at: insertionIndex)
        return reordered
    }

    private static func isNarrativeTextSegment(_ segment: ChatTurnInterleavedSegment) -> Bool {
        if case .text = segment { return true }
        return false
    }

    private static func isSubagentSegment(_ segment: ChatTurnInterleavedSegment) -> Bool {
        switch segment {
        case .subagentLiveCard, .subagentSnapshot:
            return true
        default:
            return false
        }
    }
}
