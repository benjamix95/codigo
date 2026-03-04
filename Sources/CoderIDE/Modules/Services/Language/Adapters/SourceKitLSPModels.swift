import Foundation

struct LSPPosition: Codable, Hashable, Sendable {
    let line: Int
    let character: Int
}

struct LSPRange: Codable, Hashable, Sendable {
    let start: LSPPosition
    let end: LSPPosition
}

struct LSPLocation: Codable, Hashable, Sendable {
    let uri: String
    let range: LSPRange
}

struct LSPLocationLink: Codable, Hashable, Sendable {
    let targetUri: String
    let targetRange: LSPRange
    let targetSelectionRange: LSPRange
}

struct LSPTextDocumentIdentifier: Codable, Sendable {
    let uri: String
}

struct LSPTextDocumentItem: Codable, Sendable {
    let uri: String
    let languageId: String
    let version: Int
    let text: String
}

struct LSPDidOpenTextDocumentParams: Codable, Sendable {
    let textDocument: LSPTextDocumentItem
}

struct LSPTextDocumentPositionParams: Codable, Sendable {
    let textDocument: LSPTextDocumentIdentifier
    let position: LSPPosition
}

struct LSPReferenceContext: Codable, Sendable {
    let includeDeclaration: Bool
}

struct LSPReferenceParams: Codable, Sendable {
    let textDocument: LSPTextDocumentIdentifier
    let position: LSPPosition
    let context: LSPReferenceContext
}

struct LSPRenameParams: Codable, Sendable {
    let textDocument: LSPTextDocumentIdentifier
    let position: LSPPosition
    let newName: String
}

struct LSPWorkspaceSymbolParams: Codable, Sendable {
    let query: String
}

struct LSPWorkspaceSymbolItem: Codable, Sendable {
    let name: String
    let location: LSPLocation
}

struct LSPTextEdit: Codable, Sendable {
    let range: LSPRange
    let newText: String
}

struct LSPTextDocumentEdit: Codable, Sendable {
    let textDocument: LSPTextDocumentIdentifier
    let edits: [LSPTextEdit]
}

struct LSPWorkspaceEdit: Codable, Sendable {
    let changes: [String: [LSPTextEdit]]?
    let documentChanges: [LSPDocumentChange]?
}

struct LSPDocumentChange: Codable, Sendable {
    let textDocument: LSPTextDocumentIdentifier?
    let edits: [LSPTextEdit]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.textDocument), container.contains(.edits) {
            textDocument = try container.decode(LSPTextDocumentIdentifier.self, forKey: .textDocument)
            edits = try container.decode([LSPTextEdit].self, forKey: .edits)
            return
        }
        textDocument = nil
        edits = nil
    }
}

struct LSPHoverResponse: Codable, Sendable {
    let contents: LSPHoverContents
}

enum LSPHoverContents: Codable, Sendable {
    case markup(LSPMarkupContent)
    case markedString(LSPMarkedString)
    case string(String)
    case markedStrings([LSPMarkedString])

    var plainText: String {
        switch self {
        case .markup(let markup):
            return markup.value
        case .markedString(let marked):
            return marked.value
        case .string(let value):
            return value
        case .markedStrings(let values):
            return values.map(\.value).joined(separator: "\n")
        }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let markup = try? single.decode(LSPMarkupContent.self) {
            self = .markup(markup)
            return
        }
        if let marked = try? single.decode(LSPMarkedString.self) {
            self = .markedString(marked)
            return
        }
        if let string = try? single.decode(String.self) {
            self = .string(string)
            return
        }
        if let list = try? single.decode([LSPMarkedString].self) {
            self = .markedStrings(list)
            return
        }
        throw DecodingError.typeMismatch(
            LSPHoverContents.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported hover payload")
        )
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .markup(let markup):
            try single.encode(markup)
        case .markedString(let marked):
            try single.encode(marked)
        case .string(let value):
            try single.encode(value)
        case .markedStrings(let values):
            try single.encode(values)
        }
    }
}

struct LSPMarkupContent: Codable, Sendable {
    let kind: String
    let value: String
}

struct LSPMarkedString: Codable, Sendable {
    let language: String?
    let value: String

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            language = nil
            value = raw
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        language = try keyed.decodeIfPresent(String.self, forKey: .language)
        value = try keyed.decode(String.self, forKey: .value)
    }
}
