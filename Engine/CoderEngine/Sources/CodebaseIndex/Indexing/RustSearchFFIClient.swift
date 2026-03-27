import Darwin
import Foundation
import OSLog

private let rustFFILogger = Logger(subsystem: "com.solocode.CoderEngine", category: "RustFFI")

private typealias RustVersionFn = @convention(c) () -> UnsafePointer<CChar>?
private typealias RustSearchFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias RustCoreFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias RustFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

public struct ReviewCoreLoadedState: Sendable, Equatable {
    public let loaded: Bool
    public let version: String?
    public let libraryPath: String?
    public let failureReason: String?
}

public func shouldDeferRustReviewCoreBootstrap(environment: [String: String]) -> Bool {
    if environment["SOLOCODE_REVIEW_CORE_LIBRARY_PATH"] != nil
        || environment["SOLOCODE_RUST_SEARCH_LIBRARY_PATH"] != nil
    {
        return false
    }
    if environment["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
        || environment["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1"
    {
        return true
    }
    if environment["XCTestConfigurationFilePath"] != nil
        || environment["XCInjectBundleInto"] != nil
        || environment["XCTestBundlePath"] != nil
    {
        return true
    }
    if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
        return true
    }
    if Bundle.allFrameworks.contains(where: { $0.bundlePath.contains("XCTest.framework") }) {
        return true
    }
    return NSClassFromString("XCTestCase") != nil
}

func shouldScanDerivedDataForRustReviewCoreFallback(
    environment: [String: String],
    bundleURL: URL
) -> Bool {
    for key in ["SOLOCODE_REVIEW_CORE_LIBRARY_PATH", "SOLOCODE_RUST_SEARCH_LIBRARY_PATH"] {
        if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return false
        }
    }
    return bundleURL.pathExtension.lowercased() != "app"
}

final class RustSearchFFIClient: @unchecked Sendable {
    static let shared = RustSearchFFIClient()

    private let lock = NSLock()
    private var api: RustSearchFFIApi?
    private var loadedLibraryPath: String?
    private var lastFailureReason: String?

    func performSearch(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse? {
        guard let api = resolveApi() else { return nil }
        let startedAt = Date()

        do {
            let raw = try RustSearchPayloadBuilder.makeRawJSON(
                query: query,
                snapshot: snapshot
            )
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

    func loadedReviewCoreVersion() -> String? {
        resolveApi()?.version(symbol: "review_core_version")
    }

    func reviewCoreLoadedState() -> ReviewCoreLoadedState {
        if let api = resolveApi(),
           let version = api.version(symbol: "review_core_version") {
            return ReviewCoreLoadedState(
                loaded: true,
                version: version,
                libraryPath: loadedLibraryPath,
                failureReason: nil
            )
        }
        return ReviewCoreLoadedState(
            loaded: false,
            version: nil,
            libraryPath: loadedLibraryPath,
            failureReason: lastFailureReason
        )
    }

    func callReviewFunction<T: Decodable>(
        _ functionName: String,
        payload: String
    ) throws -> T {
        guard let api = resolveApi() else {
            throw RustSearchFFIClientError.libraryUnavailable
        }
        return try api.call(functionName: functionName, payload: payload)
    }

    private func resolveApi() -> RustSearchFFIApi? {
        lock.lock()
        defer { lock.unlock() }

        if let api { return api }
        if shouldDeferRustReviewCoreBootstrap(environment: ProcessInfo.processInfo.environment) {
            lastFailureReason = "deferred_for_xctest_bootstrap"
            loadedLibraryPath = nil
            return nil
        }
        lastFailureReason = nil
        loadedLibraryPath = nil

        let candidates = Self.candidateLibraryPaths()
        rustFFILogger.debug("Rust dylib: probing \(candidates.count) candidate paths")

        for (index, candidate) in candidates.enumerated() {
            let exists = FileManager.default.fileExists(atPath: candidate)
            if !exists {
                rustFFILogger.debug("  [\(index)] MISS: \(candidate)")
                continue
            }
            rustFFILogger.debug("  [\(index)] EXISTS: \(candidate) — attempting dlopen")
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                let dlErr = Self.currentDLError() ?? "unknown"
                lastFailureReason = "dlopen_failed:\(candidate):\(dlErr)"
                rustFFILogger.error("  [\(index)] dlopen FAILED: \(dlErr)")
                continue
            }
            guard
                let versionPtr = dlsym(handle, "solocode_search_backend_version"),
                let searchPtr = dlsym(handle, "solocode_semantic_search"),
                let freePtr = dlsym(handle, "solocode_free_buffer")
            else {
                lastFailureReason = "missing_required_symbol:\(candidate)"
                rustFFILogger.error("  [\(index)] MISSING SYMBOL in \(candidate)")
                dlclose(handle)
                continue
            }

            let resolved = RustSearchFFIApi(
                handle: handle,
                versionFn: unsafeBitCast(versionPtr, to: RustVersionFn.self),
                searchFn: unsafeBitCast(searchPtr, to: RustSearchFn.self),
                freeFn: unsafeBitCast(freePtr, to: RustFreeFn.self)
            )
            loadedLibraryPath = candidate
            api = resolved
            rustFFILogger.info("Rust dylib: LOADED from \(candidate)")
            return resolved
        }

        if lastFailureReason == nil {
            lastFailureReason = "library_missing"
        }
        rustFFILogger.error("Rust dylib: FAILED — reason=\(self.lastFailureReason ?? "unknown"), tried \(candidates.count) paths")
        return nil
    }

    func resetForTests() {
        lock.lock()
        defer { lock.unlock() }
        api = nil
        loadedLibraryPath = nil
        lastFailureReason = nil
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

    func version(symbol: String) -> String? {
        guard let fn: RustVersionFn = resolve(symbol: symbol) else {
            return nil
        }
        guard let ptr = fn() else { return nil }
        return String(cString: ptr)
    }

    func callSearch<T: Decodable>(_ payload: String) throws -> T {
        try call(searchFn: searchFn, payload: payload)
    }

    func call<T: Decodable>(
        functionName: String,
        payload: String
    ) throws -> T {
        guard let fn: RustCoreFn = resolve(symbol: functionName) else {
            throw RustSearchFFIClientError.missingSymbol(functionName)
        }
        return try call(searchFn: fn, payload: payload)
    }

    private func call<T: Decodable>(
        searchFn: RustCoreFn,
        payload: String
    ) throws -> T {
        guard let encoded = payload.cString(using: .utf8) else {
            throw RustSearchFFIClientError.invalidPayloadEncoding
        }
        let resultPtr = encoded.withUnsafeBufferPointer { buffer in
            searchFn(buffer.baseAddress)
        }
        guard let resultPtr else { throw RustSearchFFIClientError.nilResponse }
        defer { freeFn(resultPtr) }

        let response = String(cString: resultPtr)
        return try JSONDecoder().decode(T.self, from: Data(response.utf8))
    }

    private func resolve<T>(symbol: String) -> T? {
        guard let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

enum RustSearchFFIClientError: Error {
    case invalidPayloadEncoding
    case nilResponse
    case libraryUnavailable
    case missingSymbol(String)
}
