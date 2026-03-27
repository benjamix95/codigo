import Foundation

enum RustSearchPayloadBuilder {
    private struct QueryEnvelope: Encodable {
        let query: SearchQueryInput
    }

    static func makeRawJSON(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) throws -> String {
        if let cachedSnapshotJSON = snapshot.rustSnapshotJSON {
            return try makeRawJSON(
                query: query,
                cachedSnapshotJSON: cachedSnapshotJSON
            )
        }

        let request = RustSearchRequestPayload(
            query: query,
            snapshot: RustSearchSnapshotPayload(from: snapshot)
        )
        let payload = try JSONEncoder().encode(request)
        guard let raw = String(data: payload, encoding: .utf8) else {
            throw RustSearchFFIClientError.invalidPayloadEncoding
        }
        return raw
    }

    static func makeRawJSON(
        query: SearchQueryInput,
        cachedSnapshotJSON: String
    ) throws -> String {
        let queryJSON = try JSONEncoder().encode(QueryEnvelope(query: query))
        guard var raw = String(data: queryJSON, encoding: .utf8),
              raw.last == "}" else {
            throw RustSearchFFIClientError.invalidPayloadEncoding
        }
        raw.removeLast()
        raw.append(",\"snapshot\":")
        raw.append(cachedSnapshotJSON)
        raw.append("}")
        return raw
    }
}

extension RustSearchSnapshotPayload {
    init(from snapshot: SemanticIndexSearchSnapshot) {
        self.chunks = snapshot.chunks.values.map {
            RustSearchChunkPayload(
                chunkId: $0.id,
                filePath: $0.filePath,
                scope: $0.scope,
                kind: $0.kind,
                content: $0.content,
                symbolNames: $0.symbolNames,
                contextualizedText: $0.contextualizedText
            )
        }
        self.invertedIndex = snapshot.invertedIndex.mapValues(Array.init)
        self.termFrequencies = snapshot.termFrequencies.mapValues { terms in
            terms.mapValues { value in Int(value) }
        }
        self.docLengths = snapshot.docLengths.mapValues { value in Int(value) }
        self.avgDocLength = snapshot.avgDocLength
        self.totalDocs = snapshot.totalDocs
        self.k1 = snapshot.k1
        self.b = snapshot.b
    }
}
