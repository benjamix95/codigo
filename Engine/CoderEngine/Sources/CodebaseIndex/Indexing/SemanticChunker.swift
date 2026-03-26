import Foundation

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

        // Tiny files (or very small symbol regions) can fall under `minChunkWeight`
        // and produce zero chunks while the file is non-empty. That breaks persistence
        // (no JSONL lines for the path) and reload/search for those paths.
        if chunks.isEmpty {
            return [makeChunk(
                filePath: indexedFile.relativePath,
                lines: lines,
                startLine: 1,
                endLine: min(lines.count, maxChunkLines),
                scope: "",
                kind: "file",
                language: indexedFile.language.rawValue,
                symbolNames: symbols.map(\.name),
                imports: indexedFile.imports
            )]
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
}

