import XCTest
@testable import CoderEngine

final class VectorSearchPersistenceTests: XCTestCase {

    // MARK: - Schema SQL validation

    func testVectorSearchSQLContainsRequiredElements() {
        let sql = PersistenceSchema.vectorSearchSQL

        // Extension
        XCTAssertTrue(sql.contains("CREATE EXTENSION IF NOT EXISTS vector"))

        // Table
        XCTAssertTrue(sql.contains("CREATE TABLE IF NOT EXISTS semantic_embeddings"))
        XCTAssertTrue(sql.contains("chunk_id        TEXT PRIMARY KEY"))
        XCTAssertTrue(sql.contains("embedding       vector(384) NOT NULL"))
        XCTAssertTrue(sql.contains("content_hash    BIGINT NOT NULL"))

        // Indexes
        XCTAssertTrue(sql.contains("idx_se_file_path"))
        XCTAssertTrue(sql.contains("idx_se_content_hash"))
        XCTAssertTrue(sql.contains("idx_se_embedding_hnsw"))
        XCTAssertTrue(sql.contains("USING hnsw"))
        XCTAssertTrue(sql.contains("vector_cosine_ops"))

        // HNSW params
        XCTAssertTrue(sql.contains("m = 16"))
        XCTAssertTrue(sql.contains("ef_construction = 64"))
    }

    func testVectorSearchSQLIsIncludedInMigration() {
        let fullSQL = PersistenceSchema.migrationSQL()
        XCTAssertTrue(fullSQL.contains("semantic_embeddings"),
                       "vectorSearchSQL must be included in migrationSQL()")
    }

    // MARK: - pgVectorLiteral format

    func testPgVectorLiteralFormat() {
        // We can't directly test private method, but we can verify through
        // the public API that embedding payloads contain float arrays.
        let payload = EmbeddingUpsertPayload(
            chunkId: "test:1:5",
            filePath: "test.swift",
            contentHash: 42,
            embedding: [0.1, 0.2, 0.3],
            scope: "TestScope",
            kind: "function",
            startLine: 1,
            endLine: 5,
            language: "swift",
            symbolNames: ["test"]
        )
        XCTAssertEqual(payload.embedding.count, 3)
        XCTAssertEqual(payload.embedding[0], 0.1, accuracy: 0.001)
    }

    // MARK: - EmbeddingUpsertPayload validation

    func testEmbeddingUpsertPayloadWith384Dims() {
        let embedding = (0..<384).map { Float($0) / 384.0 }
        let payload = EmbeddingUpsertPayload(
            chunkId: "file.swift:1:100",
            filePath: "file.swift",
            contentHash: 12345,
            embedding: embedding,
            scope: "MyModule > MyClass",
            kind: "class",
            startLine: 1,
            endLine: 100,
            language: "swift",
            symbolNames: ["MyClass", "init"]
        )
        XCTAssertEqual(payload.embedding.count, 384)
        XCTAssertEqual(payload.symbolNames.count, 2)
    }

    // MARK: - EmbeddingRecord

    func testEmbeddingRecordCodable() throws {
        let record = EmbeddingRecord(chunkId: "a:1:10", contentHash: 999)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(EmbeddingRecord.self, from: data)
        XCTAssertEqual(decoded.chunkId, "a:1:10")
        XCTAssertEqual(decoded.contentHash, 999)
    }
}
