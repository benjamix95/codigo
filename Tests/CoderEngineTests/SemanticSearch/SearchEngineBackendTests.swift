import XCTest
@testable import CoderEngine

final class SearchEngineBackendTests: XCTestCase {
    func testSemanticIndexUsesRustBackendByDefault() async {
        unsetenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND")
        let index = SemanticIndex()
        let kind = await index.configuredSearchBackendKind()
        XCTAssertEqual(kind, .rust)
    }

    func testSemanticIndexAcceptsRustBackendFlagAndKeepsSearchParity() async {
        setenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND", "rust", 1)
        defer { unsetenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND") }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-backend-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        try? """
        struct AuthManager {
            func refreshSessionToken() {}
        }
        """.write(
            to: workspace.appendingPathComponent("AuthManager.swift"),
            atomically: true,
            encoding: .utf8
        )

        let codebaseIndex = CodebaseIndex()
        _ = await codebaseIndex.indexWorkspace(paths: [workspace])
        let indexedFiles = await codebaseIndex.indexedFilesProxy()

        let rustIndex = SemanticIndex()
        let rustKind = await rustIndex.configuredSearchBackendKind()
        XCTAssertEqual(rustKind, .rust)
        await rustIndex.buildIndex(indexedFiles: indexedFiles, workspaceRoot: workspace)
        let rustResults = await rustIndex.search(query: "refresh session token", numResults: 5)
        let rustMetrics = await rustIndex.lastSearchMetricsSnapshot()

        let swiftIndex = SemanticIndex(searchBackend: SwiftSearchEngineBackend())
        await swiftIndex.buildIndex(indexedFiles: indexedFiles, workspaceRoot: workspace)
        let swiftResults = await swiftIndex.search(query: "refresh session token", numResults: 5)

        XCTAssertEqual(rustResults.map(\.chunk.filePath), swiftResults.map(\.chunk.filePath))
        XCTAssertEqual(rustResults.first?.chunk.filePath, swiftResults.first?.chunk.filePath)
        XCTAssertEqual(rustMetrics?.backendKind, .rust)
        XCTAssertEqual(rustMetrics?.usedFallback, false)
        XCTAssertEqual(rustMetrics?.loadedRustLibrary, true)
    }

    func testRustBackendFailsExplicitlyWhenRustCoreIsDisabled() async {
        setenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND", "rust", 1)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            unsetenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND")
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }
        ReviewCoreBridge.resetForTests()

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-backend-disabled-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        try? """
        struct AuthManager {
            func refreshSessionToken() {}
        }
        """.write(
            to: workspace.appendingPathComponent("AuthManager.swift"),
            atomically: true,
            encoding: .utf8
        )

        let codebaseIndex = CodebaseIndex()
        _ = await codebaseIndex.indexWorkspace(paths: [workspace])
        let indexedFiles = await codebaseIndex.indexedFilesProxy()

        let rustIndex = SemanticIndex()
        await rustIndex.buildIndex(indexedFiles: indexedFiles, workspaceRoot: workspace)
        let rustResults = await rustIndex.search(query: "refresh session token", numResults: 5)
        let rustMetrics = await rustIndex.lastSearchMetricsSnapshot()

        XCTAssertTrue(rustResults.isEmpty)
        XCTAssertEqual(rustMetrics?.backendKind, .rust)
        XCTAssertEqual(rustMetrics?.usedFallback, false)
        XCTAssertEqual(rustMetrics?.loadedRustLibrary, false)
        XCTAssertEqual(rustMetrics?.errorMessage, "Rust backend unavailable; semantic search requires Rust core")
    }

    func testRustSearchFFIClientReturnsVersionWhenLibraryIsAvailable() throws {
        guard let version = RustSearchFFIClient.shared.loadedVersion() else {
            throw XCTSkip("Rust library non disponibile in questa sessione")
        }

        XCTAssertTrue(version.contains("solocode_rust_core"))
    }

    func testReviewCoreBridgeLoadedStateReturnsVersionWhenLibraryPathIsForced() throws {
        let path = reviewCoreLibraryPath(from: #filePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Libreria review core Rust non disponibile in build/lib")
        }
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
            ReviewCoreBridge.resetForTests()
        }

        ReviewCoreBridge.resetForTests()
        let state = ReviewCoreBridge.loadedState()

        XCTAssertTrue(state.loaded)
        XCTAssertEqual(state.libraryPath, path)
        XCTAssertTrue(state.version?.contains("solocode_rust_core") == true)
        XCTAssertNil(state.failureReason)
    }
}

private extension CodebaseIndex {
    func indexedFilesProxy() -> [IndexedFile] {
        Array(indexedFiles.values)
    }
}

private func reviewCoreLibraryPath(from sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    return sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Native/RustCore/build/lib/libsolocode_rust_core.dylib")
        .path
}
