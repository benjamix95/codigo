import SwiftUI
import CoderEngine

// MARK: - Breadcrumb Store

/// Store per la navigazione breadcrumb con symbol scope corrente da CodebaseIndex.
@MainActor
final class BreadcrumbStore: ObservableObject {
    /// Segmento di breadcrumb rappresentante un componente del path o un simbolo.
    struct Segment: Identifiable, Sendable {
        let id: String
        let label: String
        let icon: String
        let kind: SegmentKind

        enum SegmentKind: Sendable {
            case folder
            case file
            case symbol(IndexedSymbol)
        }
    }

    @Published var segments: [Segment] = []
    @Published var symbolOutline: [IndexedSymbol] = []
    @Published var currentSymbol: IndexedSymbol?

    private var currentFilePath: String?
    private var rootPaths: [String] = []
    private weak var codebaseIndex: CodebaseIndex?

    func configure(codebaseIndex: CodebaseIndex, rootPaths: [String]) {
        self.codebaseIndex = codebaseIndex
        self.rootPaths = rootPaths
    }

    // MARK: - Aggiornamento

    /// Aggiorna i breadcrumb per il file e la riga corrente.
    func update(filePath: String, currentLine: Int = 1) async {
        currentFilePath = filePath
        let pathSegments = buildPathSegments(filePath: filePath)
        let symbols = await loadSymbols(filePath: filePath)
        symbolOutline = symbols

        let enclosingSymbol = findEnclosingSymbol(symbols: symbols, line: currentLine)
        currentSymbol = enclosingSymbol

        var allSegments = pathSegments
        if let enclosing = enclosingSymbol {
            allSegments.append(contentsOf: buildSymbolChain(symbol: enclosing, allSymbols: symbols))
        }

        segments = allSegments
    }

    /// Aggiorna solo il simbolo corrente senza ricalcolare il path.
    func updateLine(_ line: Int) {
        guard !symbolOutline.isEmpty else { return }

        let enclosing = findEnclosingSymbol(symbols: symbolOutline, line: line)
        guard enclosing?.id != currentSymbol?.id else { return }
        currentSymbol = enclosing

        // Ricostruisci solo la parte simboli dei segments
        let pathCount = segments.filter {
            if case .folder = $0.kind { return true }
            if case .file = $0.kind { return true }
            return false
        }.count

        var updated = Array(segments.prefix(pathCount))
        if let enclosing {
            updated.append(contentsOf: buildSymbolChain(symbol: enclosing, allSymbols: symbolOutline))
        }
        segments = updated
    }

    // MARK: - Navigazione

    /// Restituisce la riga di destinazione per un segmento cliccato.
    func lineForSegment(_ segment: Segment) -> Int? {
        if case .symbol(let sym) = segment.kind {
            return sym.line
        }
        return nil
    }

    /// Restituisce i figli diretti di un simbolo (per dropdown).
    func childrenOf(_ symbol: IndexedSymbol) -> [IndexedSymbol] {
        symbolOutline.filter { $0.containerName == symbol.name }
            .sorted { $0.line < $1.line }
    }

    /// Restituisce i simboli top-level (per dropdown dal segmento file).
    func topLevelSymbols() -> [IndexedSymbol] {
        symbolOutline.filter { $0.containerName == nil }
            .sorted { $0.line < $1.line }
    }

    // MARK: - Privato

    private func buildPathSegments(filePath: String) -> [Segment] {
        var components: [String] = []

        for root in rootPaths {
            if filePath.hasPrefix(root + "/") {
                let relative = String(filePath.dropFirst(root.count + 1))
                let rootName = (root as NSString).lastPathComponent
                components = [rootName] + relative.components(separatedBy: "/")
                break
            }
        }
        if components.isEmpty {
            components = filePath.components(separatedBy: "/").suffix(3).map { String($0) }
        }

        return components.enumerated().map { idx, comp in
            let isFile = idx == components.count - 1
            return Segment(
                id: "path:\(idx):\(comp)",
                label: comp,
                icon: isFile ? "doc.text" : "folder",
                kind: isFile ? .file : .folder
            )
        }
    }

    private func loadSymbols(filePath: String) async -> [IndexedSymbol] {
        guard let index = codebaseIndex else { return [] }

        // Converti path assoluto in relativo
        var relativePath = filePath
        for root in rootPaths {
            if filePath.hasPrefix(root + "/") {
                relativePath = String(filePath.dropFirst(root.count + 1))
                break
            }
        }

        return await index.symbolsInFile(relativePath)
    }

    private func findEnclosingSymbol(symbols: [IndexedSymbol], line: Int) -> IndexedSymbol? {
        // Trova il simbolo più specifico (più profondo) che contiene la riga
        var best: IndexedSymbol?
        for sym in symbols {
            let end = sym.endLine > 0 ? sym.endLine : sym.line
            if sym.line <= line && line <= end {
                if let current = best {
                    // Preferisci il simbolo più specifico (range più piccolo)
                    let currentRange = (current.endLine > 0 ? current.endLine : current.line) - current.line
                    let symRange = end - sym.line
                    if symRange < currentRange {
                        best = sym
                    }
                } else {
                    best = sym
                }
            }
        }
        return best
    }

    private func buildSymbolChain(symbol: IndexedSymbol, allSymbols: [IndexedSymbol]) -> [Segment] {
        var chain: [Segment] = []

        // Risali la catena dei container
        var current: IndexedSymbol? = symbol
        while let sym = current {
            chain.insert(
                Segment(
                    id: "sym:\(sym.id)",
                    label: sym.name,
                    icon: sym.kind.sfSymbol,
                    kind: .symbol(sym)
                ),
                at: 0
            )
            if let containerName = sym.containerName {
                current = allSymbols.first { $0.name == containerName && $0.containerName == nil }
            } else {
                current = nil
            }
        }

        return chain
    }
}
