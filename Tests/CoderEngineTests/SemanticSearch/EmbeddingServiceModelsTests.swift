import XCTest
@testable import CoderEngine

final class EmbeddingServiceModelsTests: XCTestCase {

    // MARK: - EmbeddingBackendKind

    func testEmbeddingBackendKindRawValues() {
        XCTAssertEqual(EmbeddingBackendKind.coreML.rawValue, "coreml")
        XCTAssertEqual(EmbeddingBackendKind.rustONNX.rawValue, "rust_onnx")
        XCTAssertEqual(EmbeddingBackendKind.pseudoHash.rawValue, "pseudo_hash")
    }

    func testEmbeddingBackendKindCodable() throws {
        let kinds: [EmbeddingBackendKind] = [.coreML, .rustONNX, .pseudoHash]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(EmbeddingBackendKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    // MARK: - EmbeddingResult

    func testEmbeddingResultInit() {
        let vector = [Float](repeating: 0.5, count: 384)
        let result = EmbeddingResult(
            text: "func hello()",
            vector: vector,
            backend: .coreML
        )
        XCTAssertEqual(result.text, "func hello()")
        XCTAssertEqual(result.vector.count, 384)
        XCTAssertEqual(result.backend, .coreML)
    }

    // MARK: - EmbeddingBatchResult

    func testEmbeddingBatchResultInit() {
        let results = [
            EmbeddingResult(text: "a", vector: [1.0], backend: .coreML),
            EmbeddingResult(text: "b", vector: [2.0], backend: .coreML),
        ]
        let batch = EmbeddingBatchResult(
            results: results,
            backend: .coreML,
            elapsedMs: 42
        )
        XCTAssertEqual(batch.results.count, 2)
        XCTAssertEqual(batch.elapsedMs, 42)
    }

    // MARK: - RustEmbedRequest

    func testRustEmbedRequestEncodable() throws {
        let request = RustEmbedRequest(texts: ["hello", "world"], modelPath: nil)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let texts = json?["texts"] as? [String]
        XCTAssertEqual(texts, ["hello", "world"])
    }

    // MARK: - RustEmbedResponse

    func testRustEmbedResponseDecodable() throws {
        let json = """
        {"embeddings": [[0.1, 0.2], [0.3, 0.4]], "error": null}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RustEmbedResponse.self, from: data)
        XCTAssertEqual(response.embeddings.count, 2)
        XCTAssertNil(response.error)
    }

    func testRustEmbedResponseWithError() throws {
        let json = """
        {"embeddings": [], "error": {"code": "fail", "message": "oops"}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RustEmbedResponse.self, from: data)
        XCTAssertEqual(response.embeddings.count, 0)
        XCTAssertEqual(response.error?.code, "fail")
        XCTAssertEqual(response.error?.message, "oops")
    }
}
