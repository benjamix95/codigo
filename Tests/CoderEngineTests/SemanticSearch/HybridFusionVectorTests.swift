import XCTest
@testable import CoderEngine

final class HybridFusionVectorTests: XCTestCase {

    // MARK: - HybridSearchSource includes vectorIndex

    func testHybridSearchSourceIncludesVectorIndex() {
        let allCases = UnifiedToolRuntime.HybridSearchSource.allCases
        XCTAssertTrue(allCases.contains(.vectorIndex), "vectorIndex must be in allCases")
        XCTAssertEqual(UnifiedToolRuntime.HybridSearchSource.vectorIndex.rawValue, "vector")
    }

    func testHybridSearchSourceCaseOrder() {
        let allCases = UnifiedToolRuntime.HybridSearchSource.allCases
        XCTAssertEqual(allCases.count, 4, "Should have 4 sources: semantic, vector, symbol, grep")
    }

    // MARK: - PersistenceSchema version

    func testPersistenceSchemaVersionIs3() {
        XCTAssertEqual(PersistenceSchema.version, 3, "Schema version should be 3 after pgvector migration")
    }

    func testMigrationSQLContainsVectorExtension() {
        let sql = PersistenceSchema.migrationSQL()
        XCTAssertTrue(sql.contains("CREATE EXTENSION IF NOT EXISTS vector"), "Migration must include pgvector extension")
        XCTAssertTrue(sql.contains("semantic_embeddings"), "Migration must include semantic_embeddings table")
        XCTAssertTrue(sql.contains("vector(384)"), "Migration must include 384-dim vector column")
        XCTAssertTrue(sql.contains("hnsw"), "Migration must include HNSW index")
    }

    // MARK: - CoreMLEmbeddingError

    func testCoreMLEmbeddingErrorDescription() {
        let error = CoreMLEmbeddingError.modelNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("all-MiniLM-L6-v2") ?? false)
    }

    // MARK: - EmbeddingService dim constant

    func testEmbeddingServiceDimIs384() {
        XCTAssertEqual(EmbeddingService.embeddingDim, 384)
        XCTAssertEqual(CoreMLEmbeddingBackend.embeddingDim, 384)
        XCTAssertEqual(RustEmbeddingBackend.embeddingDim, 384)
    }

    // MARK: - TrigramSearchModels

    func testTrigramSearchHitInit() {
        let hit = TrigramSearchHit(filePath: "a.swift", line: 10, column: 5, snippet: "func hello()")
        XCTAssertEqual(hit.filePath, "a.swift")
        XCTAssertEqual(hit.line, 10)
        XCTAssertEqual(hit.column, 5)
        XCTAssertEqual(hit.snippet, "func hello()")
        XCTAssertNotNil(hit.id)
    }

    func testTrigramSearchResultInit() {
        let hit = TrigramSearchHit(filePath: "b.swift", line: 1, column: 1, snippet: "class Foo")
        let result = TrigramSearchResult(
            matches: [hit],
            candidatesChecked: 50,
            totalFiles: 1000,
            elapsedUs: 500
        )
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.candidatesChecked, 50)
        XCTAssertEqual(result.totalFiles, 1000)
        XCTAssertEqual(result.elapsedUs, 500)
    }

    func testTrigramIndexStatusInit() {
        let status = TrigramIndexStatus(
            fileCount: 5000,
            trigramCount: 120000,
            isReady: true,
            lastBuildMs: 2500
        )
        XCTAssertEqual(status.fileCount, 5000)
        XCTAssertTrue(status.isReady)
    }

    // MARK: - VectorSearchEngineBackend kind

    func testVectorSearchEngineBackendKind() {
        let backend = VectorSearchEngineBackend()
        XCTAssertEqual(backend.kind, .vector)
        XCTAssertTrue(backend.supportsVectorSearch)
    }

    // MARK: - Default protocol extension

    func testSwiftBackendDoesNotSupportVectorSearch() {
        let backend = SwiftSearchEngineBackend()
        XCTAssertFalse(backend.supportsVectorSearch)
    }

    func testRustBackendDoesNotSupportVectorSearch() {
        let backend = RustSearchEngineBackend()
        XCTAssertFalse(backend.supportsVectorSearch)
    }
}
