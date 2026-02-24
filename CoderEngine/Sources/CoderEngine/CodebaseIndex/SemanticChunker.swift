import Foundation

// MARK: - SemanticChunk

/// A semantically meaningful piece of code extracted at AST-aware boundaries.
/// Inspired by cAST (arXiv:2506.15655): split at function/class boundaries,
/// merge small siblings, respect token limits.
public struct SemanticChunk: Sendable, Identifiable, Codable, Hashable {
    /// Unique ID: "relativePath:startLine:endLine"
    public let id: String

    /// Relative file path
    public let filePath: String

    /// Start line (1-based inclusive)
    public let startLine: Int

    /// End line (1-based inclusive)
    public let endLine: Int

    /// The actual code text of this chunk
    public let content: String

    /// Scope context (e.g. "UserService > getUser")
    public let scope: String

    /// Symbol kind (function, class, struct, etc.) or "block" for merged siblings
    public let kind: String

    /// Language
    public let language: String

    /// Symbols contained in this chunk
    public let symbolNames: [String]

    /// Imports in the file (for contextualized text)
    public let imports: [String]

    /// Non-whitespace character count (for sizing, like cAST paper)
    public let contentWeight: Int

    public init(
        filePath: String,
        startLine: Int,
        endLine: Int,
        content: String,
        scope: String,
        kind: String,
        language: String,
        symbolNames: [String] = [],
        imports: [String] = []
    ) {
        self.id = "\(filePath):\(startLine):\(endLine)"
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.content = content
        self.scope = scope
        self.kind = kind
        self.language = language
        self.symbolNames = symbolNames
        self.imports = imports
        self.contentWeight = content.filter { !$0.isWhitespace }.count
    }

    /// Contextualized text (like Supermemory): enriched representation for embedding
    public var contextualizedText: String {
        var parts: [String] = []
        parts.append("# \(filePath)")
        if !scope.isEmpty { parts.append("# Scope: \(scope)") }
        if !symbolNames.isEmpty {
            parts.append("# Defines: \(symbolNames.joined(separator: ", "))")
        }
        if !imports.isEmpty {
            parts.append("# Uses: \(imports.prefix(5).joined(separator: ", "))")
        }
        parts.append(content)
        return parts.joined(separator: "\n")
    }
}

// MARK: - SemanticChunker

/// AST-aware code chunker that splits code at semantic boundaries.
/// Uses IndexedFile symbols to identify function/class/struct boundaries,
/// then applies the greedy window algorithm from cAST paper.
public enum SemanticChunker {

    /// Maximum non-whitespace characters per chunk (approx ~200 lines of code)
    public static let maxChunkWeight = 3000

    /// Minimum non-whitespace characters to keep a chunk (avoid tiny fragments)
    public static let minChunkWeight = 50

    /// Maximum lines per chunk
    public static let maxChunkLines = 300

    /// Chunk an indexed file into semantic pieces.
    /// Strategy: use symbol boundaries from the index, then apply greedy window + merge.
    public static func chunk(indexedFile: IndexedFile, fileContent: String) -> [SemanticChunk] {
        let lines = fileContent.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        let symbols = indexedFile.symbols.sorted { $0.line < $1.line }

        // If no symbols, create a single chunk for the whole file (capped)
        if symbols.isEmpty {
            return [makeChunk(
                filePath: indexedFile.relativePath,
                lines: lines,
                startLine: 1,
                endLine: min(lines.count, maxChunkLines),
                scope: "",
                kind: "file",
                language: indexedFile.language.rawValue,
                symbolNames: [],
                imports: indexedFile.imports
            )]
        }

        // Phase 1: Extract symbol-delimited regions
        var regions = extractSymbolRegions(symbols: symbols, totalLines: lines.count)

        // Phase 2: Greedy window assignment — merge small adjacent regions
        regions = mergeSmallRegions(regions, lines: lines)

        // Phase 3: Split oversized regions
        regions = splitOversizedRegions(regions, lines: lines)

        // Phase 4: Convert regions to chunks
        var chunks: [SemanticChunk] = []
        for region in regions {
            let chunk = makeChunk(
                filePath: indexedFile.relativePath,
                lines: lines,
                startLine: region.startLine,
                endLine: region.endLine,
                scope: region.scope,
                kind: region.kind,
                language: indexedFile.language.rawValue,
                symbolNames: region.symbolNames,
                imports: indexedFile.imports
            )
            if chunk.contentWeight >= minChunkWeight {
                chunks.append(chunk)
            }
        }

        return chunks
    }

    /// Chunk from raw file content without an IndexedFile (fallback)
    public static func chunkRawFile(
        filePath: String,
        content: String,
        language: String
    ) -> [SemanticChunk] {
        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        // Simple line-based chunking with overlap
        var chunks: [SemanticChunk] = []
        var pos = 0
        let stride = maxChunkLines - 20  // 20-line overlap
        while pos < lines.count {
            let endPos = min(pos + maxChunkLines, lines.count)
            let chunk = makeChunk(
                filePath: filePath,
                lines: lines,
                startLine: pos + 1,
                endLine: endPos,
                scope: "",
                kind: "block",
                language: language,
                symbolNames: [],
                imports: []
            )
            if chunk.contentWeight >= minChunkWeight {
                chunks.append(chunk)
            }
            pos += stride
        }
        return chunks
    }

    // MARK: - Private helpers

    private struct Region {
        var startLine: Int  // 1-based
        var endLine: Int    // 1-based
        var scope: String
        var kind: String
        var symbolNames: [String]
    }

    /// Extract regions from symbol positions
    private static func extractSymbolRegions(
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
    private static func mergeSmallRegions(_ regions: [Region], lines: [String]) -> [Region] {
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
    private static func splitOversizedRegions(_ regions: [Region], lines: [String]) -> [Region] {
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
    private static func weight(lines: [String], from startLine: Int, to endLine: Int) -> Int {
        let start = max(startLine - 1, 0)
        let end = min(endLine, lines.count)
        guard start < end else { return 0 }
        return lines[start..<end].reduce(0) { $0 + $1.filter { !$0.isWhitespace }.count }
    }

    /// Create a SemanticChunk from line range
    private static func makeChunk(
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
