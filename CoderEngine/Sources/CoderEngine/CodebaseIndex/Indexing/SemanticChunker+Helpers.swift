import Foundation

// MARK: - SemanticChunker helpers

extension SemanticChunker {
    // MARK: - Internal Region Model

    struct Region {
        var startLine: Int  // 1-based
        var endLine: Int    // 1-based
        var scope: String
        var kind: String
        var symbolNames: [String]
    }

    /// Extract regions from symbol positions
    static func extractSymbolRegions(
        symbols: [IndexedSymbol],
        totalLines: Int
    ) -> [Region] {
        var regions: [Region] = []

        // Add preamble (imports, top-level code before first symbol)
        if let first = symbols.first, first.line > 1 {
            regions.append(Region(
                startLine: 1,
                endLine: first.line - 1,
                scope: "",
                kind: "preamble",
                symbolNames: []
            ))
        }

        for (i, sym) in symbols.enumerated() {
            let start = sym.line
            let end: Int
            if sym.endLine > 0 {
                end = sym.endLine
            } else if i + 1 < symbols.count {
                // End before next symbol starts
                end = symbols[i + 1].line - 1
            } else {
                end = totalLines
            }

            let scope: String
            if let container = sym.containerName {
                scope = "\(container) > \(sym.name)"
            } else {
                scope = sym.name
            }

            regions.append(Region(
                startLine: max(start, 1),
                endLine: min(max(end, start), totalLines),
                scope: scope,
                kind: sym.kind.rawValue,
                symbolNames: [sym.qualifiedName]
            ))
        }

        return regions
    }

    /// Merge adjacent small regions into larger chunks (greedy window from cAST)
    static func mergeSmallRegions(_ regions: [Region], lines: [String]) -> [Region] {
        guard regions.count > 1 else { return regions }

        var merged: [Region] = []
        var current = regions[0]

        for i in 1..<regions.count {
            let next = regions[i]
            let currentWeight = weight(lines: lines, from: current.startLine, to: current.endLine)
            let nextWeight = weight(lines: lines, from: next.startLine, to: next.endLine)
            let combinedLines = next.endLine - current.startLine + 1

            // Merge if both are small and combined size is within limits
            if currentWeight + nextWeight < maxChunkWeight && combinedLines <= maxChunkLines {
                current.endLine = next.endLine
                current.symbolNames += next.symbolNames
                if current.kind == "preamble" { current.kind = next.kind }
                if current.scope.isEmpty { current.scope = next.scope }
                else if !next.scope.isEmpty { current.scope = "\(current.scope), \(next.scope)" }
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    /// Split regions that exceed the max size
    static func splitOversizedRegions(_ regions: [Region], lines: [String]) -> [Region] {
        var result: [Region] = []
        for region in regions {
            let lineCount = region.endLine - region.startLine + 1
            if lineCount <= maxChunkLines {
                result.append(region)
                continue
            }

            // Split into maxChunkLines-sized pieces
            var pos = region.startLine
            while pos <= region.endLine {
                let end = min(pos + maxChunkLines - 1, region.endLine)
                result.append(Region(
                    startLine: pos,
                    endLine: end,
                    scope: region.scope,
                    kind: region.kind,
                    symbolNames: region.symbolNames
                ))
                pos = end + 1
            }
        }
        return result
    }

    /// Calculate non-whitespace weight for a line range
    static func weight(lines: [String], from startLine: Int, to endLine: Int) -> Int {
        let start = max(startLine - 1, 0)
        let end = min(endLine, lines.count)
        guard start < end else { return 0 }
        return lines[start..<end].reduce(0) { $0 + $1.filter { !$0.isWhitespace }.count }
    }

    /// Create a SemanticChunk from line range
    static func makeChunk(
        filePath: String,
        lines: [String],
        startLine: Int,
        endLine: Int,
        scope: String,
        kind: String,
        language: String,
        symbolNames: [String],
        imports: [String]
    ) -> SemanticChunk {
        let start = max(startLine - 1, 0)
        let end = min(endLine, lines.count)
        let content = lines[start..<end].joined(separator: "\n")

        return SemanticChunk(
            filePath: filePath,
            startLine: startLine,
            endLine: endLine,
            content: content,
            scope: scope,
            kind: kind,
            language: language,
            symbolNames: symbolNames,
            imports: imports
        )
    }
}
