import Foundation

// MARK: - SymbolKind

/// Tipo di simbolo estratto dal codice sorgente
public enum SymbolKind: String, Sendable, Codable, CaseIterable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case function
    case method
    case property
    case constant
    case variable
    case typeAlias
    case `import`
    case macro
    case interface  // TS/Java
    case trait  // Rust
    case module
    case test
    case unknown

    /// Icona SF Symbol per UI
    public var sfSymbol: String {
        switch self {
        case .class: return "c.square"
        case .struct: return "s.square"
        case .enum: return "e.square"
        case .protocol: return "p.square"
        case .extension: return "plus.square"
        case .function, .method: return "f.square"
        case .property, .variable: return "v.square"
        case .constant: return "k.square"
        case .typeAlias: return "t.square"
        case .import: return "arrow.down.square"
        case .macro: return "m.square"
        case .interface: return "i.square"
        case .trait: return "t.square"
        case .module: return "shippingbox"
        case .test: return "checkmark.square"
        case .unknown: return "questionmark.square"
        }
    }

    /// true se è un tipo (class, struct, enum, protocol, interface, trait)
    public var isType: Bool {
        switch self {
        case .class, .struct, .enum, .protocol, .interface, .trait, .typeAlias:
            return true
        default:
            return false
        }
    }

    /// true se è un callable (function, method)
    public var isCallable: Bool {
        self == .function || self == .method || self == .test
    }

    /// true se è una dichiarazione di dato (property, variable, constant)
    public var isDataDeclaration: Bool {
        self == .property || self == .variable || self == .constant
    }
}

// MARK: - AccessLevel

/// Livello di accesso del simbolo
public enum AccessLevel: String, Sendable, Codable, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case `public`
    case `open`

    private var sortOrder: Int {
        switch self {
        case .private: return 0
        case .fileprivate: return 1
        case .internal: return 2
        case .public: return 3
        case .open: return 4
        }
    }

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - IndexedSymbol

/// Simbolo estratto e indicizzato dal codice sorgente
public struct IndexedSymbol: Sendable, Identifiable, Hashable {
    /// ID univoco (filePath:line:name)
    public let id: String

    /// Nome del simbolo
    public let name: String

    /// Tipo del simbolo
    public let kind: SymbolKind

    /// Path relativo del file che contiene il simbolo
    public let filePath: String

    /// Linea nel file (1-based)
    public let line: Int

    /// Colonna nel file (1-based, 0 se sconosciuta)
    public let column: Int

    /// Linea di fine del blocco (0 se sconosciuta)
    public let endLine: Int

    /// Livello di accesso
    public let accessLevel: AccessLevel

    /// Nome completo con contesto (es. "MyClass.myMethod")
    public let qualifiedName: String

    /// Nome del tipo/scope genitore (es. "MyClass" per un metodo)
    public let containerName: String?

    /// Signature completa della dichiarazione
    public let signature: String

    /// Documentazione / commento associato
    public let documentation: String?

    /// Protocolli conformati / classi ereditate (per tipi)
    public let inherits: [String]

    /// Parametri generici
    public let genericParameters: [String]

    /// true se è static/class
    public let isStatic: Bool

    /// true se marcato @MainActor, async, ecc.
    public let annotations: [String]

    /// Linguaggio del file sorgente
    public let language: FileLanguage

    public init(
        name: String,
        kind: SymbolKind,
        filePath: String,
        line: Int,
        column: Int = 0,
        endLine: Int = 0,
        accessLevel: AccessLevel = .internal,
        qualifiedName: String? = nil,
        containerName: String? = nil,
        signature: String = "",
        documentation: String? = nil,
        inherits: [String] = [],
        genericParameters: [String] = [],
        isStatic: Bool = false,
        annotations: [String] = [],
        language: FileLanguage = .swift
    ) {
        self.id = "\(filePath):\(line):\(name)"
        self.name = name
        self.kind = kind
        self.filePath = filePath
        self.line = line
        self.column = column
        self.endLine = endLine
        self.accessLevel = accessLevel
        self.qualifiedName =
            qualifiedName ?? (containerName != nil ? "\(containerName!).\(name)" : name)
        self.containerName = containerName
        self.signature = signature.isEmpty ? name : signature
        self.documentation = documentation
        self.inherits = inherits
        self.genericParameters = genericParameters
        self.isStatic = isStatic
        self.annotations = annotations
        self.language = language
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: IndexedSymbol, rhs: IndexedSymbol) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Display

    /// Rappresentazione compatta per contesto LLM
    public var compactDescription: String {
        let access = accessLevel == .internal ? "" : "\(accessLevel.rawValue) "
        let staticPrefix = isStatic ? "static " : ""
        let kindStr = kind.rawValue
        let loc = "L\(line)"
        let container = containerName.map { " (in \($0))" } ?? ""
        return
            "\(access)\(staticPrefix)\(kindStr) \(qualifiedName)\(container) — \(filePath):\(loc)"
    }

    /// Rappresentazione dettagliata con signature
    public var detailedDescription: String {
        var lines: [String] = []
        lines.append("[\(kind.rawValue.uppercased())] \(qualifiedName)")
        lines.append("  File: \(filePath):\(line)")
        if !signature.isEmpty && signature != name {
            lines.append("  Signature: \(signature)")
        }
        if !inherits.isEmpty {
            lines.append("  Inherits: \(inherits.joined(separator: ", "))")
        }
        if !genericParameters.isEmpty {
            lines.append("  Generics: <\(genericParameters.joined(separator: ", "))>")
        }
        if !annotations.isEmpty {
            lines.append("  Annotations: \(annotations.joined(separator: ", "))")
        }
        if let doc = documentation, !doc.isEmpty {
            lines.append("  Doc: \(doc.prefix(200))")
        }
        return lines.joined(separator: "\n")
    }

    /// Outline entry per file outline (come VS Code)
    public var outlineEntry: String {
        let indent: String
        if containerName != nil {
            indent = "  "
        } else {
            indent = ""
        }
        let staticStr = isStatic ? "static " : ""
        return "\(indent)\(kind.sfSymbol) \(staticStr)\(name) (L\(line))"
    }
}

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
            parts.append("  Properties: \(data.map { $0.qualifiedName }.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - SymbolReference

/// Riferimento a un simbolo trovato in un file (uso, non definizione)
public struct SymbolReference: Sendable, Hashable {
    /// Nome del simbolo referenziato
    public let symbolName: String

    /// Path del file dove appare il riferimento
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

// MARK: - DependencyEdge

/// Arco nel grafo delle dipendenze tra file
public struct DependencyEdge: Sendable, Hashable {
    /// File sorgente (che importa)
    public let fromFile: String

    /// File target (che viene importato/usato)
    public let toFile: String

    /// Tipo di dipendenza
    public let kind: DependencyKind

    /// Simboli coinvolti (opzionale)
    public let symbols: [String]

    public init(fromFile: String, toFile: String, kind: DependencyKind, symbols: [String] = []) {
        self.fromFile = fromFile
        self.toFile = toFile
        self.kind = kind
        self.symbols = symbols
    }
}

public enum DependencyKind: String, Sendable, Codable {
    case `import`
    case inheritance
    case conformance
    case usage
}
