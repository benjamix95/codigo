import Foundation

// MARK: - SemanticIndex

/// BM25-based semantic index for code search by meaning.
/// Local alternative to Cursor's Turbopuffer vector DB:
/// - AST-aware chunks from SemanticChunker
/// - BM25 scoring (better than TF-IDF for code search)
/// - Inverted index for fast retrieval
/// - Merkle tree for incremental updates
/// - Persistence to disk (JSONL)
///
/// Pipeline:
/// 1. Chunk files at symbol boundaries (SemanticChunker)
/// 2. Tokenize chunks → inverted index
/// 3. Query: tokenize → BM25 score → rank → return top-K
public actor SemanticIndex {

    // MARK: - BM25 Parameters

    /// BM25 k1: term frequency saturation. 1.2 is standard.
    private let k1: Double = 1.2

    /// BM25 b: length normalization. 0.75 is standard.
    private let b: Double = 0.75

    // MARK: - State

    /// All indexed chunks
    private var chunks: [String: SemanticChunk] = [:]  // chunkId → chunk

    /// Inverted index: token → set of chunk IDs containing that token
    private var invertedIndex: [String: Set<String>] = [:]

    /// Term frequency per chunk: chunkId → (token → count)
    private var termFrequencies: [String: [String: Int]] = [:]

    /// Document length (token count) per chunk
    private var docLengths: [String: Int] = [:]

    /// Average document length
    private var avgDocLength: Double = 0

    /// Total number of documents (chunks)
    private var totalDocs: Int { chunks.count }

    /// Merkle tree root for change detection
    private var merkleRoot: MerkleNode?

    /// SimHash of the current codebase
    private var currentSimHash: UInt64 = 0

    /// File path → chunk IDs (for incremental removal)
    private var fileToChunks: [String: [String]] = [:]

    /// Persistence path
    private var persistencePath: URL?

    // MARK: - Init

    public init(persistencePath: URL? = nil) {
        self.persistencePath = persistencePath
    }

    // MARK: - Full Index Build

    /// Build the semantic index from a set of IndexedFiles.
    /// This is the main entry point after CodebaseIndex finishes indexing.
    public func buildIndex(
        indexedFiles: [IndexedFile],
        workspaceRoot: URL
    ) async {
        // Reset state
        chunks.removeAll()
        invertedIndex.removeAll()
        termFrequencies.removeAll()
        docLengths.removeAll()
        fileToChunks.removeAll()

        // Phase 1: Build Merkle tree for change detection
        merkleRoot = MerkleTree.build(root: workspaceRoot)
        if let root = merkleRoot {
            currentSimHash = MerkleTree.simHash(of: root)
        }

        // Phase 2: Chunk all files
        for indexed in indexedFiles {
            let content: String
            do {
                content = try String(contentsOfFile: indexed.absolutePath, encoding: .utf8)
            } catch {
                continue
            }

            let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
            addChunks(fileChunks, forFile: indexed.relativePath)
        }

        // Phase 3: Compute average doc length
        recalcAvgDocLength()

        // Phase 4: Persist if configured
        if persistencePath != nil {
            await persist()
        }
    }

    /// Incrementally update the index for changed files.
    /// Uses Merkle tree diff to find which files changed.
    public func incrementalUpdate(
        changedFiles: [IndexedFile],
        workspaceRoot: URL
    ) async {
        // Rebuild Merkle tree and diff
        let newMerkle = MerkleTree.build(root: workspaceRoot)
        if let oldRoot = merkleRoot, let newRoot = newMerkle {
            let changes = MerkleTree.diff(old: oldRoot, new: newRoot)
            merkleRoot = newRoot
            currentSimHash = MerkleTree.simHash(of: newRoot)

            // Remove chunks for removed files
            for removedPath in changes.removed {
                removeChunksForFile(removedPath)
            }
        } else {
            merkleRoot = newMerkle
            if let root = newMerkle {
                currentSimHash = MerkleTree.simHash(of: root)
            }
        }

        // Re-chunk changed files
        for indexed in changedFiles {
            removeChunksForFile(indexed.relativePath)

            let content: String
            do {
                content = try String(contentsOfFile: indexed.absolutePath, encoding: .utf8)
            } catch {
                continue
            }

            let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
            addChunks(fileChunks, forFile: indexed.relativePath)
        }

        recalcAvgDocLength()
    }

    /// Update a single file (called from FileWatcher)
    public func updateFile(_ indexed: IndexedFile) {
        removeChunksForFile(indexed.relativePath)

        let content: String
        do {
            content = try String(contentsOfFile: indexed.absolutePath, encoding: .utf8)
        } catch {
            return
        }

        let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
        addChunks(fileChunks, forFile: indexed.relativePath)
        recalcAvgDocLength()
    }

    /// Remove all semantic chunks for a single file.
    public func removeFile(_ relativePath: String) {
        removeChunksForFile(relativePath)
        recalcAvgDocLength()
    }

    /// Clear the entire semantic index state.
    public func clear() {
        chunks.removeAll()
        invertedIndex.removeAll()
        termFrequencies.removeAll()
        docLengths.removeAll()
        avgDocLength = 0
        merkleRoot = nil
        currentSimHash = 0
        fileToChunks.removeAll()
    }

    // MARK: - Search

    /// Semantic search: query by natural language, return ranked chunks.
    /// This is the core BM25 search pipeline.
    public func search(
        query: String,
        targetDirectories: [String] = [],
        numResults: Int = 25
    ) -> [SearchResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        // Score all documents using BM25
        var scores: [String: Double] = [:]

        for token in Set(queryTokens) {
            guard let postingList = invertedIndex[token] else { continue }

            // IDF: log((N - df + 0.5) / (df + 0.5) + 1)
            let df = Double(postingList.count)
            let n = Double(totalDocs)
            let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)

            for chunkId in postingList {
                // Directory filter
                if !targetDirectories.isEmpty {
                    guard let chunk = chunks[chunkId],
                          targetDirectories.contains(where: { chunk.filePath.hasPrefix($0) })
                    else { continue }
                }

                let tf = Double(termFrequencies[chunkId]?[token] ?? 0)
                let dl = Double(docLengths[chunkId] ?? 1)
                let avgDl = max(avgDocLength, 1.0)

                // BM25 score
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDl))
                scores[chunkId, default: 0] += idf * tfNorm
            }
        }

        // Boost: add bonuses for query tokens in symbol names, scope, file path
        for (chunkId, _) in scores {
            guard let chunk = chunks[chunkId] else { continue }
            var bonus = 0.0

            let queryLower = query.lowercased()
            let queryTokensLower = Set(queryTokens)

            // Symbol name match bonus
            for sym in chunk.symbolNames {
                let symLower = sym.lowercased()
                if symLower.contains(queryLower) { bonus += 5.0 }
                for token in queryTokensLower where symLower.contains(token) {
                    bonus += 1.5
                }
            }

            // Scope match bonus
            let scopeLower = chunk.scope.lowercased()
            for token in queryTokensLower where scopeLower.contains(token) {
                bonus += 1.0
            }

            // File path match bonus (file name semantics)
            let fileNameLower = (chunk.filePath as NSString).lastPathComponent.lowercased()
            for token in queryTokensLower where token.count >= 3 && fileNameLower.contains(token) {
                bonus += 2.0
            }

            // Kind-specific bonus: prioritize definitions over data
            if ["class", "struct", "protocol", "enum", "interface"].contains(chunk.kind) {
                bonus += 0.5
            } else if ["function", "method"].contains(chunk.kind) {
                bonus += 0.3
            }

            scores[chunkId] = (scores[chunkId] ?? 0) + bonus
        }

        // Rank and return top-K
        let ranked = scores.sorted { $0.value > $1.value }
            .prefix(numResults)
            .compactMap { (chunkId, score) -> SearchResult? in
                guard let chunk = chunks[chunkId] else { return nil }
                return SearchResult(chunk: chunk, score: score)
            }

        return Array(ranked)
    }

    // MARK: - Status

    /// Current index statistics
    public func status() -> IndexStatus {
        IndexStatus(
            totalChunks: chunks.count,
            totalTokens: invertedIndex.count,
            totalFiles: fileToChunks.count,
            avgDocLength: avgDocLength,
            simHash: currentSimHash,
            hasMerkleTree: merkleRoot != nil
        )
    }

    public struct IndexStatus: Sendable {
        public let totalChunks: Int
        public let totalTokens: Int
        public let totalFiles: Int
        public let avgDocLength: Double
        public let simHash: UInt64
        public let hasMerkleTree: Bool
    }

    // MARK: - Search Result

    public struct SearchResult: Sendable {
        public let chunk: SemanticChunk
        public let score: Double

        /// Formatted output line
        public var displayLine: String {
            let lineInfo = chunk.startLine == chunk.endLine
                ? ":\(chunk.startLine)"
                : ":\(chunk.startLine)-\(chunk.endLine)"
            let scopeInfo = chunk.scope.isEmpty ? "" : " [\(chunk.scope)]"
            return "\(chunk.filePath)\(lineInfo)\(scopeInfo) (score: \(String(format: "%.2f", score)))"
        }
    }

    // MARK: - Tokenization

    /// Tokenize text for BM25 indexing.
    /// Handles: camelCase splitting, snake_case splitting, lowercasing, stopword removal.
    /// Also generates synonym expansions for common programming concepts.
    private func tokenize(_ text: String) -> [String] {
        Self.tokenizeStatic(text)
    }

    /// Static tokenizer (usable without actor isolation)
    nonisolated static func tokenizeStatic(_ text: String) -> [String] {
        var tokens: [String] = []

        // Split by non-alphanumeric chars
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for word in words {
            let lower = word.lowercased()
            tokens.append(lower)

            // CamelCase splitting: "handleLogin" → ["handle", "login"]
            let camelSplit = splitCamelCase(word).map { $0.lowercased() }.filter { $0.count >= 2 }
            if camelSplit.count > 1 {
                tokens.append(contentsOf: camelSplit)
            }
        }

        // Remove stopwords
        let filtered = tokens.filter { !stopWords.contains($0) }

        // Add synonym expansions
        var expanded = filtered
        for token in filtered {
            if let syns = synonymMap[token] {
                expanded.append(contentsOf: syns.prefix(2))
            }
        }

        return expanded
    }

    /// Split camelCase: "handleLogin" → ["handle", "Login"]
    private static func splitCamelCase(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for char in word {
            if char.isUppercase && !current.isEmpty {
                parts.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Programming stopwords (not useful for semantic search)
    private static let stopWords: Set<String> = [
        "the", "is", "at", "in", "of", "to", "for", "and", "or", "not",
        "this", "that", "with", "from", "by", "on", "an", "be", "as",
        "it", "if", "do", "does", "did", "has", "have", "had", "was",
        "were", "are", "am", "been", "being", "where", "when", "how",
        "what", "which", "who", "whom", "whose", "why",
        "var", "let", "val", "const", "int", "string", "bool", "void",
        "return", "import", "public", "private", "internal", "static",
    ]

    /// Synonym map for semantic expansion
    private static let synonymMap: [String: [String]] = [
        "auth": ["authentication", "login", "signin", "credential"],
        "authentication": ["auth", "login", "signin"],
        "login": ["auth", "signin", "authenticate"],
        "save": ["persist", "store", "write", "serialize"],
        "persist": ["save", "store", "write"],
        "load": ["fetch", "read", "deserialize", "parse"],
        "fetch": ["load", "get", "retrieve", "request"],
        "delete": ["remove", "destroy", "cleanup", "purge"],
        "remove": ["delete", "destroy", "cleanup"],
        "error": ["exception", "failure", "fault", "crash"],
        "exception": ["error", "failure", "throw"],
        "handle": ["manage", "process", "dispatch"],
        "handler": ["controller", "manager", "processor"],
        "config": ["configuration", "settings", "preferences"],
        "configuration": ["config", "settings", "options"],
        "test": ["spec", "assert", "expect", "verify"],
        "network": ["http", "api", "request", "response"],
        "api": ["endpoint", "route", "network", "rest"],
        "view": ["screen", "page", "component", "layout"],
        "render": ["display", "draw", "show", "present"],
        "data": ["model", "entity", "schema", "record"],
        "model": ["data", "entity", "schema", "struct"],
        "cache": ["memo", "memoize", "buffer", "store"],
        "validate": ["check", "verify", "assert", "ensure"],
        "user": ["account", "profile", "member"],
        "submit": ["send", "post", "confirm", "complete"],
        "click": ["tap", "press", "trigger", "activate"],
        "password": ["credential", "secret", "passphrase"],
        "database": ["db", "storage", "persistence", "repository"],
        "db": ["database", "storage", "datastore"],
        "navigate": ["route", "redirect", "go", "push"],
        "route": ["navigate", "path", "endpoint", "url"],
    ]

    // MARK: - Index Management (Private)

    /// Add chunks to the index
    private func addChunks(_ newChunks: [SemanticChunk], forFile relativePath: String) {
        var chunkIds: [String] = []

        for chunk in newChunks {
            chunks[chunk.id] = chunk
            chunkIds.append(chunk.id)

            // Tokenize the contextualized text
            let tokens = tokenize(chunk.contextualizedText)
            var tf: [String: Int] = [:]
            for token in tokens {
                tf[token, default: 0] += 1
            }
            termFrequencies[chunk.id] = tf
            docLengths[chunk.id] = tokens.count

            // Update inverted index
            for token in tf.keys {
                invertedIndex[token, default: []].insert(chunk.id)
            }
        }

        fileToChunks[relativePath] = chunkIds
    }

    /// Remove all chunks for a file
    private func removeChunksForFile(_ relativePath: String) {
        guard let chunkIds = fileToChunks[relativePath] else { return }

        for chunkId in chunkIds {
            // Remove from inverted index
            if let tf = termFrequencies[chunkId] {
                for token in tf.keys {
                    invertedIndex[token]?.remove(chunkId)
                    if invertedIndex[token]?.isEmpty == true {
                        invertedIndex.removeValue(forKey: token)
                    }
                }
            }

            // Remove chunk data
            chunks.removeValue(forKey: chunkId)
            termFrequencies.removeValue(forKey: chunkId)
            docLengths.removeValue(forKey: chunkId)
        }

        fileToChunks.removeValue(forKey: relativePath)
    }

    /// Recalculate average document length
    private func recalcAvgDocLength() {
        let totalLength = docLengths.values.reduce(0, +)
        avgDocLength = docLengths.isEmpty ? 0 : Double(totalLength) / Double(docLengths.count)
    }

    // MARK: - Persistence

    /// Save index to disk as JSONL
    private func persist() async {
        guard let path = persistencePath else { return }
        let encoder = JSONEncoder()
        var lines: [String] = []
        for chunk in chunks.values {
            if let data = try? encoder.encode(chunk),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        let content = lines.joined(separator: "\n")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Load index from disk
    public func loadFromDisk() async {
        guard let path = persistencePath,
              let content = try? String(contentsOf: path, encoding: .utf8)
        else { return }

        let decoder = JSONDecoder()
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var loadedChunks: [SemanticChunk] = []

        for line in lines {
            if let data = line.data(using: .utf8),
               let chunk = try? decoder.decode(SemanticChunk.self, from: data) {
                loadedChunks.append(chunk)
            }
        }

        // Rebuild index from loaded chunks
        for chunk in loadedChunks {
            addChunks([chunk], forFile: chunk.filePath)
        }
        recalcAvgDocLength()
    }
}
