import Foundation

// MARK: - SemanticChunk

/// A semantically meaningful piece of code extracted at AST-aware boundaries.
public struct SemanticChunk: Sendable, Identifiable, Codable, Hashable {
    /// Unique ID: "relativePath:startLine:endLine"
    public let id: String

    /// Relative file path
    public let filePath: String

    /// Start line (1-based inclusive)
    public let startLine: Int

    /// End line (1-based inclusive)
    public let endLine: Int

    /// The actual code text of this chunk
    public let content: String

    /// Scope context (e.g. "UserService > getUser")
    public let scope: String

    /// Symbol kind (function, class, struct, etc.) or "block" for merged siblings
    public let kind: String

    /// Language
    public let language: String

    /// Symbols contained in this chunk
    public let symbolNames: [String]

    /// Imports in the file (for contextualized text)
    public let imports: [String]

    /// Non-whitespace character count (for sizing, like cAST paper)
    public let contentWeight: Int

    public init(
        filePath: String,
        startLine: Int,
        endLine: Int,
        content: String,
        scope: String,
        kind: String,
        language: String,
        symbolNames: [String] = [],
        imports: [String] = []
    ) {
        self.id = "\(filePath):\(startLine):\(endLine)"
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.content = content
        self.scope = scope
        self.kind = kind
        self.language = language
        self.symbolNames = symbolNames
        self.imports = imports
        self.contentWeight = content.filter { !$0.isWhitespace }.count
    }

    /// Contextualized text (like Supermemory): enriched representation for embedding
    public var contextualizedText: String {
        var parts: [String] = []
        parts.append("# \(filePath)")
        if !scope.isEmpty { parts.append("# Scope: \(scope)") }
        if !symbolNames.isEmpty {
            parts.append("# Defines: \(symbolNames.joined(separator: ", "))")
        }
        if !imports.isEmpty {
            parts.append("# Uses: \(imports.prefix(5).joined(separator: ", "))")
        }
        parts.append(content)
        return parts.joined(separator: "\n")
    }
}
