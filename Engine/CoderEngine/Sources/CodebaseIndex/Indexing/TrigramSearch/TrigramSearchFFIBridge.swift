import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "TrigramFFI")

// MARK: - TrigramSearchFFIBridge

/// Bridges Swift calls to the Rust trigram index via the existing FFI dylib.
enum TrigramSearchFFIBridge {

    /// Build the trigram index from a list of files.
    static func buildIndex(files: [(path: String, content: String, contentHash: UInt64)]) -> TrigramBuildResponse? {
        let entries = files.map { TrigramBuildFileEntry(path: $0.path, content: $0.content, contentHash: $0.contentHash) }
        let request = TrigramBuildRequest(files: entries)
        return callFFI("solocode_trigram_index_build", request: request)
    }

    /// Search using the trigram index.
    static func search(
        pattern: String,
        maxResults: Int = 200,
        caseSensitive: Bool = false,
        fileContents: [UInt32: String]? = nil
    ) -> TrigramSearchResponse? {
        let request = TrigramSearchRequest(
            pattern: pattern,
            maxResults: maxResults,
            caseSensitive: caseSensitive,
            fileContents: fileContents
        )
        return callFFI("solocode_trigram_search", request: request)
    }

    /// Update the index with changed files.
    static func updateIndex(files: [(path: String, content: String, contentHash: UInt64)]) -> Bool {
        let entries = files.map { TrigramBuildFileEntry(path: $0.path, content: $0.content, contentHash: $0.contentHash) }
        let request = TrigramBuildRequest(files: entries)
        let _: TrigramBuildResponse? = callFFI("solocode_trigram_update", request: request)
        return true
    }

    // MARK: - Private

    private static func callFFI<Req: Encodable, Resp: Decodable>(
        _ functionName: String,
        request: Req
    ) -> Resp? {
        let client = RustSearchFFIClient.shared
        guard client.loadedVersion() != nil else {
            logger.warning("Rust dylib not loaded — trigram FFI unavailable")
            return nil
        }

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let payload = try encoder.encode(request)
            guard let jsonString = String(data: payload, encoding: .utf8) else { return nil }

            let response: Resp = try client.callReviewFunction(functionName, payload: jsonString)
            return response
        } catch {
            logger.error("Trigram FFI call \(functionName) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
