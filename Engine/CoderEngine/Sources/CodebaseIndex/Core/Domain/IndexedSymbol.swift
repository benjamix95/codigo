import Foundation

// MARK: - IndexedSymbol

/// Simbolo estratto e indicizzato dal codice sorgente
public struct IndexedSymbol: Sendable, Identifiable, Hashable, Codable {
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

    /// Fully qualified name with context (e.g. "MyClass.myMethod")
    public let qualifiedName: String

    /// Nome del tipo/scope genitore (es. "MyClass" per un metodo)
    public let containerName: String?

    /// Signature completa della dichiarazione
    public let signature: String

    /// Documentazione / commento associato
    public let documentation: String?

    /// Protocolli conformati / classi ereditate (per tipi)
    public let inherits: [String]

    /// Generic parameters
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
