import Foundation

// MARK: - IndexedFile

/// Risultato dell'indicizzazione di un singolo file
public struct IndexedFile: Sendable {
    /// Path relativo del file
    public let relativePath: String

    /// Path assoluto del file
    public let absolutePath: String

    /// Linguaggio
    public let language: FileLanguage

    /// Simboli estratti dal file
    public let symbols: [IndexedSymbol]

    /// Imports trovati
    public let imports: [String]

    /// Numero di linee nel file
    public let lineCount: Int

    /// Dimensione file in byte
    public let size: UInt64

    /// Timestamp indicizzazione
    public let indexedAt: Date

    /// Hash del contenuto per invalidazione cache
    public let contentHash: UInt64

    public init(
        relativePath: String,
        absolutePath: String,
        language: FileLanguage,
        symbols: [IndexedSymbol],
        imports: [String],
        lineCount: Int,
        size: UInt64,
        indexedAt: Date = .now,
        contentHash: UInt64 = 0
    ) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.language = language
        self.symbols = symbols
        self.imports = imports
        self.lineCount = lineCount
        self.size = size
        self.indexedAt = indexedAt
        self.contentHash = contentHash
    }

    /// Outline testuale del file (tutti i simboli con indentazione)
    public var outline: String {
        if symbols.isEmpty {
            return "  (no symbols)"
        }
        return symbols.map { $0.outlineEntry }.joined(separator: "\n")
    }

    /// Sommario compatto per contesto LLM
    public var summary: String {
        var parts: [String] = []
        parts.append("📄 \(relativePath) (\(language.rawValue), \(lineCount) lines)")
        if !imports.isEmpty {
            parts.append("  Imports: \(imports.joined(separator: ", "))")
        }
        let types = symbols.filter { $0.kind.isType }
        let callables = symbols.filter { $0.kind.isCallable }
        let data = symbols.filter { $0.kind.isDataDeclaration }
        if !types.isEmpty {
            parts.append("  Types: \(types.map { $0.name }.joined(separator: ", "))")
        }
        if !callables.isEmpty {
            parts.append(
                "  Functions: \(callables.map { $0.qualifiedName }.joined(separator: ", "))")
        }
        if !data.isEmpty {
            parts.append(
                "  Properties: \(data.map { $0.qualifiedName }.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }
}
