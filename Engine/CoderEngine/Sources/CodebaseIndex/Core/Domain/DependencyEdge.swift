import Foundation

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
