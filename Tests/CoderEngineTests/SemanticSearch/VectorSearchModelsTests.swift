import XCTest
@testable import CoderEngine

final class VectorSearchModelsTests: XCTestCase {

    // MARK: - VectorSearchHit

    func testVectorSearchHitInit() {
        let hit = VectorSearchHit(
            id: "file.swift:10:20",
            filePath: "file.swift",
            score: 0.85,
            startLine: 10,
            endLine: 20,
            scope: "MyClass > myFunc",
            kind: "function",
            language: "swift",
            symbolNames: ["myFunc"]
        )
        XCTAssertEqual(hit.id, "file.swift:10:20")
        XCTAssertEqual(hit.filePath, "file.swift")
        XCTAssertEqual(hit.score, 0.85, accuracy: 0.001)
        XCTAssertEqual(hit.startLine, 10)
        XCTAssertEqual(hit.endLine, 20)
        XCTAssertEqual(hit.scope, "MyClass > myFunc")
        XCTAssertEqual(hit.kind, "function")
        XCTAssertEqual(hit.language, "swift")
        XCTAssertEqual(hit.symbolNames, ["myFunc"])
    }

    func testVectorSearchHitCodable() throws {
        let hit = VectorSearchHit(
            id: "a.swift:1:5",
            filePath: "a.swift",
            score: 0.92,
            startLine: 1,
            endLine: 5,
            scope: "",
            kind: "class",
            language: "swift",
            symbolNames: []
        )
        let data = try JSONEncoder().encode(hit)
        let decoded = try JSONDecoder().decode(VectorSearchHit.self, from: data)
        XCTAssertEqual(decoded.id, hit.id)
        XCTAssertEqual(decoded.score, hit.score, accuracy: 0.001)
    }

    // MARK: - EmbeddingRecord

    func testEmbeddingRecordInit() {
        let record = EmbeddingRecord(chunkId: "test:1:10", contentHash: 12345)
        XCTAssertEqual(record.chunkId, "test:1:10")
        XCTAssertEqual(record.contentHash, 12345)
    }

    // MARK: - EmbeddingUpsertPayload

    func testEmbeddingUpsertPayloadInit() {
        let embedding = [Float](repeating: 0.1, count: 384)
        let payload = EmbeddingUpsertPayload(
            chunkId: "file.swift:1:20",
            filePath: "file.swift",
            contentHash: 999,
            embedding: embedding,
            scope: "MyClass",
            kind: "class",
            startLine: 1,
            endLine: 20,
            language: "swift",
            symbolNames: ["MyClass"]
        )
        XCTAssertEqual(payload.chunkId, "file.swift:1:20")
        XCTAssertEqual(payload.embedding.count, 384)
        XCTAssertEqual(payload.symbolNames, ["MyClass"])
    }

    // MARK: - SearchEngineBackendKind

    func testSearchEngineBackendKindIncludesVector() {
        let kind = SearchEngineBackendKind.vector
        XCTAssertEqual(kind.rawValue, "vector")

        let hybrid = SearchEngineBackendKind.hybrid
        XCTAssertEqual(hybrid.rawValue, "hybrid")
    }

    func testSearchEngineBackendKindCodable() throws {
        let kinds: [SearchEngineBackendKind] = [.swift, .rust, .vector, .hybrid]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(SearchEngineBackendKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }
}
