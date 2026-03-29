import Foundation

/// A segment in the interleaved chat timeline.
/// Segments are sorted by `sequence` so text, reasoning, and tool
/// operations appear in chronological order within a single turn.
enum ChatTurnInterleavedSegment: Identifiable {
    case text(id: String, content: String, sequence: Int)
    case reasoning(id: String, text: String, sequence: Int)
    case toolEvent(id: String, event: ToolTraceEvent, sequence: Int)
    case toolGroup(id: String, group: ChatTurnToolEventGroup, sequence: Int)
    case subagentLiveCard(id: String, card: SwarmLiveCardState, sequence: Int)
    case subagentSnapshot(id: String, snapshot: SubagentCardSnapshot, sequence: Int)
    case artifact(id: String, block: PersistedChatTimelineBlock, sequence: Int)

    var id: String {
        switch self {
        case .text(let id, _, _): return "seg-text-\(id)"
        case .reasoning(let id, _, let sequence): return "seg-reason-\(id)-\(sequence)"
        case .toolEvent(let id, _, _): return "seg-trace-\(id)"
        case .toolGroup(let id, _, _): return "seg-trace-group-\(id)"
        case .subagentLiveCard(let id, _, _): return "seg-live-subagent-\(id)"
        case .subagentSnapshot(let id, _, _): return "seg-snapshot-subagent-\(id)"
        case .artifact(let id, _, _): return "seg-artifact-\(id)"
        }
    }

    var sequence: Int {
        switch self {
        case .text(_, _, let s): return s
        case .reasoning(_, _, let s): return s
        case .toolEvent(_, _, let s): return s
        case .toolGroup(_, _, let s): return s
        case .subagentLiveCard(_, _, let s): return s
        case .subagentSnapshot(_, _, let s): return s
        case .artifact(_, _, let s): return s
        }
    }
}

enum ChatTurnToolEventGroupCategory: String, Equatable {
    case exploration
    case terminal
    case edit
}

struct ChatTurnToolEventGroup: Equatable {
    let id: String
    let category: ChatTurnToolEventGroupCategory
    let events: [ToolTraceEvent]
    let sequence: Int
}
