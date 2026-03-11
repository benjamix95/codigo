import XCTest
@testable import CoderEngine

final class SearchEngineBackendTests: XCTestCase {
    func testSemanticIndexUsesSwiftBackendByDefault() async {
        unsetenv("SOLOCODE_SEMANTIC_SEARCH_BACKEND")
        let index = SemanticIndex()
        let kind = await index.configuredSearchBackendKind()
        XCTAssertEqual(kind, .swift)
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
        XCTAssertEqual(rustMetrics?.usedFallback, RustSearchFFIClient.shared.loadedVersion() == nil)
    }

    func testRustSearchFFIClientReturnsVersionWhenLibraryIsAvailable() throws {
        guard let version = RustSearchFFIClient.shared.loadedVersion() else {
            throw XCTSkip("Rust library non disponibile in questa sessione")
        }

        XCTAssertTrue(version.contains("solocode_rust_core"))
    }
}

private extension CodebaseIndex {
    func indexedFilesProxy() -> [IndexedFile] {
        Array(indexedFiles.values)
    }
}
