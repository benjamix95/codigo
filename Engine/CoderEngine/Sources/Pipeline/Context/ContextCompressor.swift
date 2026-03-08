import Foundation

// MARK: - CompressionStrategy

/// Strategie di compressione del contesto (§8.3).
public enum CompressionStrategy: String, Sendable, Equatable, CaseIterable {
    case dependencyPruning = "dependency_pruning"
    case astCompression = "ast_compression"
    case semanticSummarization = "semantic_summarization"

    public var typicalRatio: Double {
        switch self {
        case .dependencyPruning: return 10.0
        case .astCompression: return 3.0
        case .semanticSummarization: return 5.0
        }
    }
}

// MARK: - CompressionConfig

/// Soglie di compressione configurabili (§8.3).
public struct CompressionConfig: Sendable, Equatable {
    public var softLimitTokens: Int
    public var hardLimitTokens: Int

    public init(
        softLimitTokens: Int = 32_000,
        hardLimitTokens: Int = 64_000
    ) {
        self.softLimitTokens = softLimitTokens
        self.hardLimitTokens = hardLimitTokens
    }
}

// MARK: - CompressionResult

/// Risultato della compressione con metriche.
public struct CompressionResult: Sendable, Equatable {
    public let items: [CompressedItem]
    public let originalTokens: Int
    public let compressedTokens: Int
    public let strategiesApplied: [CompressionStrategy]

    public var compressionRatio: Double {
        guard compressedTokens > 0 else { return 0 }
        return Double(originalTokens) / Double(compressedTokens)
    }

    public init(
        items: [CompressedItem],
        originalTokens: Int,
        compressedTokens: Int,
        strategiesApplied: [CompressionStrategy]
    ) {
        self.items = items
        self.originalTokens = originalTokens
        self.compressedTokens = compressedTokens
        self.strategiesApplied = strategiesApplied
    }
}

// MARK: - CompressedItem

/// Item di contesto dopo compressione.
public struct CompressedItem: Sendable, Equatable {
    public let filePath: String
    public let originalTokens: Int
    public let compressedTokens: Int
    public let strategy: CompressionStrategy?
    public let isProtected: Bool

    public init(
        filePath: String,
        originalTokens: Int,
        compressedTokens: Int,
        strategy: CompressionStrategy?,
        isProtected: Bool
    ) {
        self.filePath = filePath
        self.originalTokens = originalTokens
        self.compressedTokens = compressedTokens
        self.strategy = strategy
        self.isProtected = isProtected
    }
}

// MARK: - ContextCompressorInput

/// Input per la compressione, con scope di protezione.
public struct ContextCompressorInput: Sendable {
    public let items: [ContextCompressorItem]
    public let fileScope: Set<String>
    public let symbolScope: Set<String>

    public init(
        items: [ContextCompressorItem],
        fileScope: Set<String>,
        symbolScope: Set<String> = []
    ) {
        self.items = items
        self.fileScope = fileScope
        self.symbolScope = symbolScope
    }
}

// MARK: - ContextCompressorItem

/// Singolo item in input alla compressione.
public struct ContextCompressorItem: Sendable {
    public let filePath: String
    public let tokenCount: Int
    public let dependencyDepth: Int
    public let isTestFile: Bool

    public init(
        filePath: String,
        tokenCount: Int,
        dependencyDepth: Int = 0,
        isTestFile: Bool = false
    ) {
        self.filePath = filePath
        self.tokenCount = tokenCount
        self.dependencyDepth = dependencyDepth
        self.isTestFile = isTestFile
    }
}

// MARK: - ContextCompressor

/// Compressore di contesto con 3 strategie progressive (§8.3).
///
/// Pipeline compressione:
/// ```
/// if context_tokens > hard_limit:
///   apply dependency_pruning
///   if still > hard_limit:
///     apply ast_compression
///     if still > hard_limit:
///       apply semantic_summarization
/// elif context_tokens > soft_limit:
///   apply ast_compression (solo file non in scope diretto)
/// ```
///
/// File in `file_scope` del task MUST MAI essere compressi.
/// Test file correlati SHOULD essere mantenuti integri.
public struct ContextCompressor: Sendable {

    public let config: CompressionConfig

    public init(config: CompressionConfig = CompressionConfig()) {
        self.config = config
    }

    // MARK: - Compress

    /// Applica la pipeline di compressione sugli item forniti.
    public func compress(
        _ input: ContextCompressorInput
    ) -> CompressionResult {
        let totalTokens = input.items.reduce(0) { $0 + $1.tokenCount }

        guard totalTokens > config.softLimitTokens else {
            return noCompression(input.items, total: totalTokens)
        }

        var compressed = input.items.map { item in
            CompressedItem(
                filePath: item.filePath,
                originalTokens: item.tokenCount,
                compressedTokens: item.tokenCount,
                strategy: nil,
                isProtected: input.fileScope.contains(item.filePath)
                    || item.isTestFile
            )
        }
        var strategies: [CompressionStrategy] = []

        if totalTokens > config.hardLimitTokens {
            compressed = applyDependencyPruning(
                compressed, input: input
            )
            strategies.append(.dependencyPruning)

            if currentTotal(compressed) > config.hardLimitTokens {
                compressed = applyASTCompression(
                    compressed, input: input
                )
                strategies.append(.astCompression)

                if currentTotal(compressed) > config.hardLimitTokens {
                    compressed = applySemanticSummarization(
                        compressed
                    )
                    strategies.append(.semanticSummarization)
                }
            }
        } else {
            compressed = applyASTCompression(
                compressed, input: input, directScopeOnly: true
            )
            strategies.append(.astCompression)
        }

        return CompressionResult(
            items: compressed,
            originalTokens: totalTokens,
            compressedTokens: currentTotal(compressed),
            strategiesApplied: strategies
        )
    }

    // MARK: - Strategies

    private func applyDependencyPruning(
        _ items: [CompressedItem],
        input: ContextCompressorInput
    ) -> [CompressedItem] {
        items.compactMap { compressed in
            guard !compressed.isProtected else { return compressed }
            let source = input.items.first {
                $0.filePath == compressed.filePath
            }
            guard let depth = source?.dependencyDepth,
                  depth > 2
            else {
                return compressed
            }
            return CompressedItem(
                filePath: compressed.filePath,
                originalTokens: compressed.originalTokens,
                compressedTokens: 0,
                strategy: .dependencyPruning,
                isProtected: false
            )
        }
    }

    private func applyASTCompression(
        _ items: [CompressedItem],
        input: ContextCompressorInput,
        directScopeOnly: Bool = false
    ) -> [CompressedItem] {
        items.map { compressed in
            guard !compressed.isProtected,
                  compressed.compressedTokens > 0
            else {
                return compressed
            }
            if directScopeOnly,
               input.fileScope.contains(compressed.filePath) {
                return compressed
            }
            let ratio = CompressionStrategy.astCompression.typicalRatio
            let newTokens = max(
                Int(Double(compressed.compressedTokens) / ratio), 1
            )
            return CompressedItem(
                filePath: compressed.filePath,
                originalTokens: compressed.originalTokens,
                compressedTokens: newTokens,
                strategy: .astCompression,
                isProtected: false
            )
        }
    }

    private func applySemanticSummarization(
        _ items: [CompressedItem]
    ) -> [CompressedItem] {
        items.map { compressed in
            guard !compressed.isProtected,
                  compressed.compressedTokens > 0
            else {
                return compressed
            }
            let ratio = CompressionStrategy
                .semanticSummarization.typicalRatio
            let newTokens = max(
                Int(Double(compressed.compressedTokens) / ratio), 1
            )
            return CompressedItem(
                filePath: compressed.filePath,
                originalTokens: compressed.originalTokens,
                compressedTokens: newTokens,
                strategy: .semanticSummarization,
                isProtected: false
            )
        }
    }

    // MARK: - Helpers

    private func currentTotal(_ items: [CompressedItem]) -> Int {
        items.reduce(0) { $0 + $1.compressedTokens }
    }

    private func noCompression(
        _ items: [ContextCompressorItem],
        total: Int
    ) -> CompressionResult {
        CompressionResult(
            items: items.map {
                CompressedItem(
                    filePath: $0.filePath,
                    originalTokens: $0.tokenCount,
                    compressedTokens: $0.tokenCount,
                    strategy: nil,
                    isProtected: false
                )
            },
            originalTokens: total,
            compressedTokens: total,
            strategiesApplied: []
        )
    }
}
