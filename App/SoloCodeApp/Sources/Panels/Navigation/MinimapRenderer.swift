import Foundation
import CoderEngine

// MARK: - Minimap Renderer

/// Genera i dati per il rendering della minimap (code overview laterale).
/// Converte simboli e righe di codice in regioni colorate.
struct MinimapRenderer: Sendable {
    /// Regione nella minimap rappresentante un simbolo o blocco di codice.
    struct Region: Identifiable, Sendable {
        let id: String
        let startLine: Int
        let endLine: Int
        let kind: RegionKind
        let label: String
        let depth: Int
    }

    enum RegionKind: Sendable {
        case type       // class, struct, enum, protocol
        case callable   // function, method
        case property   // property, variable, constant
        case `import`   // import statement
        case comment    // commento
        case other

        var hue: Double {
            switch self {
            case .type: return 0.75       // viola
            case .callable: return 0.08   // arancione
            case .property: return 0.35   // verde
            case .import: return 0.55     // ciano
            case .comment: return 0.30    // verde chiaro
            case .other: return 0.0       // grigio
            }
        }
    }

    /// Rappresenta la viewport visibile nell'editor.
    struct Viewport: Sendable {
        let startLine: Int
        let endLine: Int
    }

    /// Dati completi per il rendering della minimap.
    struct RenderData: Sendable {
        let totalLines: Int
        let regions: [Region]
        let viewport: Viewport
    }

    // MARK: - Rendering

    /// Genera i dati di render dalla lista di simboli e dal contenuto del file.
    static func render(
        symbols: [IndexedSymbol],
        totalLines: Int,
        viewport: Viewport
    ) -> RenderData {
        let regions = buildRegions(from: symbols)
        return RenderData(
            totalLines: max(totalLines, 1),
            regions: regions,
            viewport: viewport
        )
    }

    /// Calcola la posizione Y normalizzata (0...1) per una riga.
    static func normalizedY(line: Int, totalLines: Int) -> CGFloat {
        guard totalLines > 1 else { return 0 }
        return CGFloat(line - 1) / CGFloat(totalLines - 1)
    }

    /// Calcola l'altezza normalizzata di una regione.
    static func normalizedHeight(startLine: Int, endLine: Int, totalLines: Int) -> CGFloat {
        guard totalLines > 1 else { return 0.01 }
        return max(CGFloat(endLine - startLine + 1) / CGFloat(totalLines), 0.005)
    }

    /// Converte una posizione Y normalizzata in un numero di riga.
    static func lineFromNormalizedY(_ y: CGFloat, totalLines: Int) -> Int {
        let line = Int(y * CGFloat(totalLines - 1)) + 1
        return max(1, min(line, totalLines))
    }

    // MARK: - Privato

    private static func buildRegions(from symbols: [IndexedSymbol]) -> [Region] {
        symbols.compactMap { sym -> Region? in
            let end = sym.endLine > 0 ? sym.endLine : sym.line
            let kind = regionKind(for: sym.kind)
            let depth = sym.containerName != nil ? 1 : 0

            return Region(
                id: sym.id,
                startLine: sym.line,
                endLine: end,
                kind: kind,
                label: sym.name,
                depth: depth
            )
        }
        .sorted { $0.startLine < $1.startLine }
    }

    private static func regionKind(for symbolKind: SymbolKind) -> RegionKind {
        if symbolKind.isType { return .type }
        if symbolKind.isCallable { return .callable }
        if symbolKind.isDataDeclaration { return .property }
        if symbolKind == .import { return .import }
        return .other
    }
}
