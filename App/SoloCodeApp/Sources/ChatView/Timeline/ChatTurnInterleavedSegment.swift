import Foundation

/// A segment in the interleaved chat timeline.
/// Segments are sorted by `sequence` so text, reasoning, and tool
/// operations appear in chronological order within a single turn.
enum ChatTurnInterleavedSegment: Identifiable {
    case text(id: String, content: String, sequence: Int)
    case reasoning(id: String, text: String, sequence: Int)
    case toolTrace(id: String, events: [ToolTraceEvent], sequence: Int)
    case artifact(id: String, block: PersistedChatTimelineBlock, sequence: Int)

    var id: String {
        switch self {
        case .text(let id, _, _): return "seg-text-\(id)"
        case .reasoning(let id, _, _): return "seg-reason-\(id)"
        case .toolTrace(let id, _, _): return "seg-trace-\(id)"
        case .artifact(let id, _, _): return "seg-artifact-\(id)"
        }
    }

    var sequence: Int {
        switch self {
        case .text(_, _, let s): return s
        case .reasoning(_, _, let s): return s
        case .toolTrace(_, _, let s): return s
        case .artifact(_, _, let s): return s
        }
    }
}
