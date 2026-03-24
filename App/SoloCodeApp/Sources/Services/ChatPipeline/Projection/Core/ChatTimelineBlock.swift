import Foundation

enum ChatTimelineBlockKind: String, Codable, Equatable {
    case primaryText
    case reasoning
    case mermaid
    case commands
    case files
    case status
    case plan
    case toolTrace
    /// Placeholder emitted by Rust to mark where tool trace events
    /// should be inserted in the interleaved timeline.
    case toolMarker
}

struct PersistedChatTimelineBlock: Identifiable, Codable, Equatable {
    var id: String
    var kind: ChatTimelineBlockKind
    var title: String?
    var text: String
    var items: [String]
    var metadata: [String: String]
    var isCollapsible: Bool
    var isCollapsedByDefault: Bool
    /// Ordering sequence for interleaved timeline rendering.
    /// Blocks and tool trace events are sorted by this value.
    var sequence: Int

    init(
        id: String,
        kind: ChatTimelineBlockKind,
        title: String? = nil,
        text: String = "",
        items: [String] = [],
        metadata: [String: String] = [:],
        isCollapsible: Bool = false,
        isCollapsedByDefault: Bool = false,
        sequence: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.items = items
        self.metadata = metadata
        self.isCollapsible = isCollapsible
        self.isCollapsedByDefault = isCollapsedByDefault
        self.sequence = sequence
    }
}
