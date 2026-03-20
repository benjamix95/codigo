import Foundation

enum ChatArtifactKind: String, Codable, Equatable {
    case mermaid
    case commands
    case files
    case status
    case plan
    case toolTrace
}

struct ChatArtifact: Identifiable, Codable, Equatable {
    var id: String
    var kind: ChatArtifactKind
    var title: String
    var text: String
    var items: [String]
    var metadata: [String: String]
    var isCollapsible: Bool
    var isCollapsedByDefault: Bool

    init(
        id: String,
        kind: ChatArtifactKind,
        title: String,
        text: String = "",
        items: [String] = [],
        metadata: [String: String] = [:],
        isCollapsible: Bool = true,
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
