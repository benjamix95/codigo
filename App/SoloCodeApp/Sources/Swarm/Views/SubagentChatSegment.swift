import Foundation

/// A segment in the sub-agent chat, analogous to `ChatTurnInterleavedSegment`
/// in the main chat. Built from `SubagentTranscriptEntry` arrays by the
/// `SubagentChatSegmentBuilder`.
enum SubagentChatSegment: Identifiable {
    /// The task/prompt assigned to this sub-agent (shown as user message).
    case taskPrompt(id: String, text: String)
    /// Reasoning/thinking output — rendered as collapsible ThinkingBlockView.
    case reasoning(id: String, blocks: [ReasoningBlock], isLive: Bool)
    /// Assistant text response — rendered as MarkdownContentView.
    case text(id: String, content: String, isStreaming: Bool)
    /// Tool operations — rendered as MessageToolTraceView.
    case toolTrace(id: String, events: [ToolTraceEvent])
    /// Final result/summary — rendered as a green result bubble.
    case result(id: String, text: String, timestamp: Date?)

    var id: String {
        switch self {
        case .taskPrompt(let id, _): return "sa-prompt-\(id)"
        case .reasoning(let id, _, _): return "sa-reason-\(id)"
        case .text(let id, _, _): return "sa-text-\(id)"
        case .toolTrace(let id, _): return "sa-trace-\(id)"
        case .result(let id, _, _): return "sa-result-\(id)"
        }
    }
}
