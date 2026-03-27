import Foundation
@testable import CoderEngine
import XCTest

final class RustSearchPayloadBuilderTests: XCTestCase {
    func testMakeRawJSONReusesCachedSnapshotJSON() throws {
        let cachedSnapshotJSON = """
        {"chunks":[],"invertedIndex":{},"termFrequencies":{},"docLengths":{},"avgDocLength":0,"totalDocs":0,"k1":1.2,"b":0.75}
        """
        let snapshot = SemanticIndexSearchSnapshot(
            chunks: [:],
            invertedIndex: [:],
            termFrequencies: [:],
            docLengths: [:],
            avgDocLength: 0,
            totalDocs: 0,
            k1: 1.2,
            b: 0.75,
            simHash: 42,
            rustSnapshotJSON: cachedSnapshotJSON
        )

        let raw = try RustSearchPayloadBuilder.makeRawJSON(
            query: SearchQueryInput(query: "auth flow", targetDirectories: ["Sources"], numResults: 5),
            snapshot: snapshot
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        let query = try XCTUnwrap(object["query"] as? [String: Any])
        let decodedSnapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])

        XCTAssertEqual(query["query"] as? String, "auth flow")
        XCTAssertEqual(query["numResults"] as? Int, 5)
        XCTAssertEqual(decodedSnapshot["totalDocs"] as? Int, 0)
    }
}
