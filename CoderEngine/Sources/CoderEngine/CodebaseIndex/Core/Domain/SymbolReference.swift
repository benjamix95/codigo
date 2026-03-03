import Foundation

// MARK: - SymbolReference

/// Riferimento a un simbolo trovato in un file (uso, non definizione)
public struct SymbolReference: Sendable, Hashable {
    /// Nome del simbolo referenziato
    public let symbolName: String

    /// Path del file dove appare
    public let filePath: String

    /// Linea dove appare
    public let line: Int

    /// Snippet di contesto (la riga intera)
    public let contextLine: String

    /// true se è la definizione stessa
    public let isDefinition: Bool

    public init(
        symbolName: String,
        filePath: String,
        line: Int,
        contextLine: String = "",
        isDefinition: Bool = false
    ) {
        self.symbolName = symbolName
        self.filePath = filePath
        self.line = line
        self.contextLine = contextLine
        self.isDefinition = isDefinition
    }

    public var description: String {
        let kind = isDefinition ? "DEF" : "REF"
        return "[\(kind)] \(filePath):\(line) — \(contextLine.trimmingCharacters(in: .whitespaces))"
    }
}
