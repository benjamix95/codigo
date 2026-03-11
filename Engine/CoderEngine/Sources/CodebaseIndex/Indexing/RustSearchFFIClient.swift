import Darwin
import Foundation

private typealias RustVersionFn = @convention(c) () -> UnsafePointer<CChar>?
private typealias RustSearchFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias RustFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

final class RustSearchFFIClient: @unchecked Sendable {
    static let shared = RustSearchFFIClient()

    private let lock = NSLock()
    private var api: RustSearchFFIApi?
    private var resolutionAttempted = false

    func performSearch(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse? {
        guard let api = resolveApi() else { return nil }
        let startedAt = Date()

        do {
            let request = RustSearchRequestPayload(
                query: query,
                snapshot: RustSearchSnapshotPayload(from: snapshot)
            )
            let payload = try JSONEncoder().encode(request)
            guard let raw = String(data: payload, encoding: .utf8) else {
                return nil
            }
            let response: RustSearchResponsePayload = try api.callSearch(raw)
            let finishedAt = Date()
            return SearchEngineBackendResponse(
                hits: response.hits,
                metrics: SearchBackendMetrics(
                    backendKind: .rust,
                    elapsedMs: max(Int(finishedAt.timeIntervalSince(startedAt) * 1000), 0),
                    hitCount: response.hits.count,
                    usedFallback: false,
                    loadedRustLibrary: true,
                    errorMessage: response.error?.message
                )
            )
        } catch {
            return nil
        }
    }

    func loadedVersion() -> String? {
        resolveApi()?.version()
    }

    private func resolveApi() -> RustSearchFFIApi? {
        lock.lock()
        defer { lock.unlock() }

        if let api { return api }
        if resolutionAttempted { return nil }
        resolutionAttempted = true

        for candidate in Self.candidateLibraryPaths() where FileManager.default.fileExists(atPath: candidate) {
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else { continue }
            guard
                let versionPtr = dlsym(handle, "solocode_search_backend_version"),
                let searchPtr = dlsym(handle, "solocode_semantic_search"),
                let freePtr = dlsym(handle, "solocode_free_buffer")
            else {
                dlclose(handle)
                continue
            }

            let resolved = RustSearchFFIApi(
                handle: handle,
                versionFn: unsafeBitCast(versionPtr, to: RustVersionFn.self),
                searchFn: unsafeBitCast(searchPtr, to: RustSearchFn.self),
                freeFn: unsafeBitCast(freePtr, to: RustFreeFn.self)
            )
            api = resolved
            return resolved
        }

        return nil
    }

    private static func candidateLibraryPaths() -> [String] {
        var candidates: [String] = []
        let explicit = ProcessInfo.processInfo.environment["SOLOCODE_RUST_SEARCH_LIBRARY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            candidates.append(explicit)
        }

        let repoRelative = "\(FileManager.default.currentDirectoryPath)/Native/RustCore/build/lib/libsolocode_rust_core.dylib"
        candidates.append(repoRelative)

        var cursor = Bundle.main.bundleURL
        for _ in 0..<4 {
            cursor.deleteLastPathComponent()
            candidates.append(cursor.appendingPathComponent("solocode_rust/libsolocode_rust_core.dylib").path)
            candidates.append(cursor.appendingPathComponent("libsolocode_rust_core.dylib").path)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}

private struct RustSearchFFIApi {
    let handle: UnsafeMutableRawPointer
    let versionFn: RustVersionFn
    let searchFn: RustSearchFn
    let freeFn: RustFreeFn

    func version() -> String? {
        guard let ptr = versionFn() else { return nil }
        return String(cString: ptr)
    }

    func callSearch<T: Decodable>(_ payload: String) throws -> T {
        guard let encoded = payload.cString(using: .utf8) else {
            throw RustSearchFFIClientError.invalidPayloadEncoding
        }
        let resultPtr = encoded.withUnsafeBufferPointer { buffer in
            searchFn(buffer.baseAddress)
        }
        guard let resultPtr else { throw RustSearchFFIClientError.nilResponse }
        defer { freeFn(resultPtr) }

        let response = String(cString: resultPtr)
        let data = Data(response.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private enum RustSearchFFIClientError: Error {
    case invalidPayloadEncoding
    case nilResponse
}

private extension RustSearchSnapshotPayload {
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
        self.invertedIndex = snapshot.invertedIndex.mapValues { Array($0) }
        self.termFrequencies = snapshot.termFrequencies.mapValues {
            $0.mapValues { Int($0) }
        }
        self.docLengths = snapshot.docLengths.mapValues { Int($0) }
        self.avgDocLength = snapshot.avgDocLength
        self.totalDocs = snapshot.totalDocs
        self.k1 = snapshot.k1
        self.b = snapshot.b
    }
}
