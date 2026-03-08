import Foundation

public enum RuntimeLanguageSource: String, Sendable {
    case sourceKitLSP = "sourcekit_lsp"
    case localIndex = "local_index"
}

public struct RuntimeLanguageLocation: Sendable {
    public let filePath: String
    public let line: Int
    public let column: Int?
    public let symbolName: String
    public let source: RuntimeLanguageSource

    public init(
        filePath: String,
        line: Int,
        column: Int?,
        symbolName: String,
        source: RuntimeLanguageSource
    ) {
        self.filePath = filePath
        self.line = line
        self.column = column
        self.symbolName = symbolName
        self.source = source
    }
}

public struct RuntimeLanguageRenamePlan: Sendable {
    public let oldName: String
    public let newName: String
    public let references: [RuntimeLanguageLocation]
    public let source: RuntimeLanguageSource

    public init(
        oldName: String,
        newName: String,
        references: [RuntimeLanguageLocation],
        source: RuntimeLanguageSource
    ) {
        self.oldName = oldName
        self.newName = newName
        self.references = references
        self.source = source
    }
}

public protocol RuntimeLanguageService: Sendable {
    func goToDefinition(symbol: String, fileHint: String?) async throws -> [RuntimeLanguageLocation]
    func findReferences(symbol: String, limit: Int) async throws -> [RuntimeLanguageLocation]
    func rename(oldName: String, newName: String) async throws -> RuntimeLanguageRenamePlan
}
