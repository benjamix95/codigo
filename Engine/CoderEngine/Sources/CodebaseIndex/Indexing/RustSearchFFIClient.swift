import Darwin
import Foundation
import OSLog

private let rustFFILogger = Logger(subsystem: "com.codigo.CoderEngine", category: "RustFFI")

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
        rustFFILogger.info("Rust dylib: probing \(candidates.count) candidate paths")

        for (index, candidate) in candidates.enumerated() {
            let exists = FileManager.default.fileExists(atPath: candidate)
            if !exists {
                rustFFILogger.debug("  [\(index)] MISS: \(candidate)")
                continue
            }
            rustFFILogger.info("  [\(index)] EXISTS: \(candidate) — attempting dlopen")
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

    private static func candidateLibraryPaths() -> [String] {
        var candidates: [String] = []
        let env = ProcessInfo.processInfo.environment
        let libName = "libsolocode_rust_core.dylib"
        let subdir = "solocode_rust"

        for key in ["SOLOCODE_REVIEW_CORE_LIBRARY_PATH", "SOLOCODE_RUST_SEARCH_LIBRARY_PATH"] {
            guard let path = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { continue }
            candidates.append(path)
        }

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDir.appendingPathComponent("\(subdir)/\(libName)").path)
        }
        for relativePath in [
            "Contents/MacOS/\(subdir)/\(libName)",
            "Contents/Resources/\(subdir)/\(libName)",
        ] {
            candidates.append(Bundle.main.bundleURL.appendingPathComponent(relativePath).path)
        }

        if let builtProducts = env["BUILT_PRODUCTS_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !builtProducts.isEmpty {
            candidates.append("\(builtProducts)/\(subdir)/\(libName)")
        }
        if let srcRoot = env["SRCROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !srcRoot.isEmpty {
            candidates.append("\(srcRoot)/Native/RustCore/build/lib/\(libName)")
            candidates.append("\(srcRoot)/Native/target/debug/\(libName)")
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/Native/target/debug/\(libName)")
        candidates.append("\(cwd)/Native/RustCore/build/lib/\(libName)")

        if let workspace = env["SOLOCODE_WORKSPACE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !workspace.isEmpty {
            candidates.append("\(workspace)/Native/target/debug/\(libName)")
            candidates.append("\(workspace)/Native/RustCore/build/lib/\(libName)")
        }

        scanDerivedDataForDylib(libName, subdir: subdir, into: &candidates)

        var cursor = Bundle.main.bundleURL
        for _ in 0..<4 {
            cursor.deleteLastPathComponent()
            candidates.append(cursor.appendingPathComponent("\(subdir)/\(libName)").path)
            candidates.append(cursor.appendingPathComponent(libName).path)
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func scanDerivedDataForDylib(
        _ libName: String,
        subdir: String,
        into candidates: inout [String]
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derivedData, includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("Solo_Code-") {
            for config in ["Debug", "Release"] {
                let path = entry
                    .appendingPathComponent("Build/Products/\(config)/Solo Code.app/Contents/MacOS/\(subdir)/\(libName)")
                candidates.append(path.path)
            }
        }
    }

    private static func currentDLError() -> String? {
        guard let error = dlerror() else { return nil }
        return String(cString: error)
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

private enum RustSearchFFIClientError: Error {
    case invalidPayloadEncoding
    case nilResponse
    case libraryUnavailable
    case missingSymbol(String)
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

public enum ReviewCoreBridge {
    public static func loadedVersion() -> String? {
        RustSearchFFIClient.shared.loadedReviewCoreVersion()
    }

    public static func loadedState() -> ReviewCoreLoadedState {
        RustSearchFFIClient.shared.reviewCoreLoadedState()
    }

    public static func call<Request: Encodable, Response: Decodable>(
        functionName: String,
        request: Request
    ) -> Response? {
        guard isEnabled else { return nil }
        do {
            let payload = try JSONEncoder().encode(request)
            guard let raw = String(data: payload, encoding: .utf8) else {
                return nil
            }
            return try RustSearchFFIClient.shared.callReviewFunction(functionName, payload: raw)
        } catch {
            return nil
        }
    }

    public static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        let forceSwift = env["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
            || env["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1"
        return !forceSwift
            && !shouldDeferRustReviewCoreBootstrap(environment: env)
            && loadedVersion() != nil
    }

    public static func resetForTests() {
        RustSearchFFIClient.shared.resetForTests()
    }
}

