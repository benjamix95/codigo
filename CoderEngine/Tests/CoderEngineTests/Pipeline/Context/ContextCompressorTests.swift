import XCTest
@testable import CoderEngine

final class ContextCompressorTests: XCTestCase {

    // MARK: - No Compression Needed

    func testNoCompression_underSoftLimit() {
        let compressor = ContextCompressor()
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "a.swift", tokenCount: 1000
                ),
            ],
            fileScope: Set(["a.swift"])
        )
        let result = compressor.compress(input)
        XCTAssertTrue(result.strategiesApplied.isEmpty)
        XCTAssertEqual(result.originalTokens, result.compressedTokens)
    }

    // MARK: - Soft Limit (AST Compression only)

    func testSoftLimit_appliesASTOnly() {
        let config = CompressionConfig(
            softLimitTokens: 1000, hardLimitTokens: 5000
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "a.swift", tokenCount: 800
                ),
                ContextCompressorItem(
                    filePath: "b.swift", tokenCount: 800
                ),
            ],
            fileScope: Set(["a.swift"])
        )
        let result = compressor.compress(input)
        XCTAssertEqual(result.strategiesApplied, [.astCompression])
        XCTAssertLessThan(result.compressedTokens, result.originalTokens)
    }

    // MARK: - Hard Limit (Progressive Compression)

    func testHardLimit_appliesDependencyPruning() {
        let config = CompressionConfig(
            softLimitTokens: 1000, hardLimitTokens: 2000
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "a.swift", tokenCount: 1000
                ),
                ContextCompressorItem(
                    filePath: "deep.swift", tokenCount: 2000,
                    dependencyDepth: 3
                ),
            ],
            fileScope: Set(["a.swift"])
        )
        let result = compressor.compress(input)
        XCTAssertTrue(
            result.strategiesApplied.contains(.dependencyPruning)
        )
    }

    func testHardLimit_deepDeps_pruned() {
        let config = CompressionConfig(
            softLimitTokens: 100, hardLimitTokens: 500
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "core.swift", tokenCount: 300
                ),
                ContextCompressorItem(
                    filePath: "trans.swift", tokenCount: 400,
                    dependencyDepth: 4
                ),
            ],
            fileScope: Set(["core.swift"])
        )
        let result = compressor.compress(input)
        let transItem = result.items.first { $0.filePath == "trans.swift" }
        XCTAssertEqual(transItem?.compressedTokens, 0)
    }

    // MARK: - Protected Files

    func testProtected_fileScope_neverCompressed() {
        let config = CompressionConfig(
            softLimitTokens: 100, hardLimitTokens: 200
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "main.swift", tokenCount: 500
                ),
            ],
            fileScope: Set(["main.swift"])
        )
        let result = compressor.compress(input)
        let mainItem = result.items.first { $0.filePath == "main.swift" }
        XCTAssertEqual(
            mainItem?.compressedTokens,
            mainItem?.originalTokens
        )
    }

    func testProtected_testFiles_neverCompressed() {
        let config = CompressionConfig(
            softLimitTokens: 100, hardLimitTokens: 200
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "Test.swift", tokenCount: 500,
                    isTestFile: true
                ),
            ],
            fileScope: Set()
        )
        let result = compressor.compress(input)
        let testItem = result.items.first { $0.filePath == "Test.swift" }
        XCTAssertEqual(
            testItem?.compressedTokens,
            testItem?.originalTokens
        )
    }

    // MARK: - Compression Ratio

    func testCompressionRatio_computed() {
        let result = CompressionResult(
            items: [], originalTokens: 1000,
            compressedTokens: 200,
            strategiesApplied: [.astCompression]
        )
        XCTAssertEqual(result.compressionRatio, 5.0, accuracy: 0.01)
    }

    func testCompressionRatio_zeroCompressed() {
        let result = CompressionResult(
            items: [], originalTokens: 1000,
            compressedTokens: 0,
            strategiesApplied: []
        )
        XCTAssertEqual(result.compressionRatio, 0)
    }

    // MARK: - Strategy Ratios

    func testStrategyTypicalRatios() {
        XCTAssertEqual(
            CompressionStrategy.dependencyPruning.typicalRatio, 10.0
        )
        XCTAssertEqual(
            CompressionStrategy.astCompression.typicalRatio, 3.0
        )
        XCTAssertEqual(
            CompressionStrategy.semanticSummarization.typicalRatio, 5.0
        )
    }

    // MARK: - Full Pipeline

    func testFullPipeline_multipleStrategies() {
        let config = CompressionConfig(
            softLimitTokens: 100, hardLimitTokens: 200
        )
        let compressor = ContextCompressor(config: config)
        let input = ContextCompressorInput(
            items: [
                ContextCompressorItem(
                    filePath: "a.swift", tokenCount: 100
                ),
                ContextCompressorItem(
                    filePath: "b.swift", tokenCount: 100
                ),
                ContextCompressorItem(
                    filePath: "c.swift", tokenCount: 100
                ),
            ],
            fileScope: Set()
        )
        let result = compressor.compress(input)
        XCTAssertLessThan(result.compressedTokens, result.originalTokens)
        XCTAssertFalse(result.strategiesApplied.isEmpty)
    }
}
