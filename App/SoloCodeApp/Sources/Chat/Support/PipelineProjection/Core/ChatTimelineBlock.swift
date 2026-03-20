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

    init(
        id: String,
        kind: ChatTimelineBlockKind,
        title: String? = nil,
        text: String = "",
        items: [String] = [],
        metadata: [String: String] = [:],
        isCollapsible: Bool = false,
        isCollapsedByDefault: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.items = items
        self.metadata = metadata
        self.isCollapsible = isCollapsible
        self.isCollapsedByDefault = isCollapsedByDefault
    }
}
