import Foundation

enum EditorPaneID: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
}

enum EditorDiagnosticSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
    case hint
}

enum EditorBottomPanel: String, Codable, CaseIterable, Sendable {
    case problems
    case references
    case outline
}

enum EditorBridgeRequestKind: String, Codable, Sendable {
    case hoverRequested
    case definitionRequested
    case referencesRequested
    case renameRequested
    case outlineRequested
    case formatRequested
}

struct EditorCursorPosition: Equatable, Sendable {
    let pane: EditorPaneID
    let line: Int
    let column: Int
}

struct EditorSelectionRange: Equatable, Sendable {
    let pane: EditorPaneID
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}

struct EditorDiagnostic: Identifiable, Hashable, Sendable {
    let id: String
    let filePath: String
    let line: Int
    let column: Int
    let endLine: Int
    let endColumn: Int
    let severity: EditorDiagnosticSeverity
    let message: String
    let source: String
}

struct EditorDiagnosticSummary: Equatable, Sendable {
    let errors: Int
    let warnings: Int

    static let empty = EditorDiagnosticSummary(errors: 0, warnings: 0)
}

struct EditorNavigationTarget: Identifiable, Hashable, Sendable {
    let id: String
    let filePath: String
    let line: Int
    let column: Int
    let symbolName: String
    let source: String

    init(
        filePath: String,
        line: Int,
        column: Int,
        symbolName: String,
        source: String
    ) {
        self.id = "\(filePath):\(line):\(column):\(symbolName)"
        self.filePath = filePath
        self.line = line
        self.column = column
        self.symbolName = symbolName
        self.source = source
    }
}

struct EditorSymbolItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let line: Int
    let column: Int
    let iconName: String
}

struct EditorQuickOpenResult: Identifiable, Hashable, Sendable {
    let path: String
    let displayPath: String
    let score: Int

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
}

struct MonacoRequestContext: Codable, Sendable {
    let requestId: String
    let pane: String
    let path: String
    let word: String
    let line: Int
    let column: Int
    let selectionStartLine: Int?
    let selectionStartColumn: Int?
    let selectionEndLine: Int?
    let selectionEndColumn: Int?
    let newName: String?

    var paneID: EditorPaneID { EditorPaneID(rawValue: pane) ?? .primary }
}

struct MonacoMarkerPayload: Codable, Sendable {
    let path: String
    let markers: [Marker]

    struct Marker: Codable, Sendable {
        let message: String
        let severity: Int
        let source: String?
        let startLineNumber: Int
        let startColumn: Int
        let endLineNumber: Int
        let endColumn: Int
    }
}

struct MonacoActionPayload: Codable, Sendable {
    let pane: String
    let path: String
    let commandId: String
    let line: Int?
}

struct MonacoResolvedResponse<T: Codable & Sendable>: Codable, Sendable {
    let requestId: String
    let payload: T
}

struct MonacoHoverPayload: Codable, Sendable {
    let contents: String?
}

struct MonacoDefinitionPayload: Codable, Sendable {
    let locations: [Location]

    struct Location: Codable, Sendable {
        let filePath: String
        let line: Int
        let column: Int
        let symbolName: String
        let source: String
    }
}

struct MonacoRenamePayload: Codable, Sendable {
    let edits: [Edit]

    struct Edit: Codable, Sendable {
        let filePath: String
        let line: Int
        let column: Int
        let endColumn: Int
        let text: String
    }
}

struct MonacoOutlinePayload: Codable, Sendable {
    let symbols: [Symbol]

    struct Symbol: Codable, Sendable {
        let name: String
        let detail: String
        let line: Int
        let column: Int
        let iconName: String
    }
}
