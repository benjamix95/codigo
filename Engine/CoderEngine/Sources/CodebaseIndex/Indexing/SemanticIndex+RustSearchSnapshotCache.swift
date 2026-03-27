import Foundation

extension SemanticIndex {
    func cachedRustSearchSnapshotJSON() -> String? {
        if cachedRustSearchSnapshotSimHash == currentSimHash,
           let cachedRustSearchSnapshotJSONString {
            return cachedRustSearchSnapshotJSONString
        }

        let snapshot = SemanticIndexSearchSnapshot(
            chunks: chunks,
            invertedIndex: invertedIndex,
            termFrequencies: termFrequencies,
            docLengths: docLengths,
            avgDocLength: avgDocLength,
            totalDocs: totalDocs,
            k1: k1,
            b: b,
            simHash: currentSimHash
        )
        let payload = RustSearchSnapshotPayload(from: snapshot)

        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        cachedRustSearchSnapshotSimHash = currentSimHash
        cachedRustSearchSnapshotJSONString = json
        return json
    }

    func invalidateCachedRustSearchSnapshot() {
        cachedRustSearchSnapshotSimHash = nil
        cachedRustSearchSnapshotJSONString = nil
    }
}
