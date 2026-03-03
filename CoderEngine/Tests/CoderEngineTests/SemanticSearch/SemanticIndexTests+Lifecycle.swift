import Foundation
import XCTest
@testable import CoderEngine

extension SemanticIndexTests {

    // MARK: - Incremental Update

    func testUpdateFileUpdatesIndex() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)
        let statusBefore = await index.status()

        // Add a new file
        let newContent = """
        class NetworkManager {
            func fetch(url: String) -> Data {
                return Data()
            }
        }
        """
        let newPath = tmpDir.appendingPathComponent("NetworkManager.swift")
        try! newContent.write(to: newPath, atomically: true, encoding: .utf8)

        let newFile = IndexedFile(
            relativePath: "NetworkManager.swift",
            absolutePath: newPath.path,
            language: .swift,
            symbols: [
                IndexedSymbol(name: "NetworkManager", kind: .class, filePath: "NetworkManager.swift", line: 1, endLine: 5, language: .swift),
                IndexedSymbol(name: "fetch", kind: .method, filePath: "NetworkManager.swift", line: 2, endLine: 4, containerName: "NetworkManager", language: .swift),
            ],
            imports: [],
            lineCount: 6,
            size: UInt64(newContent.utf8.count)
        )
        await index.updateFile(newFile)
        let statusAfter = await index.status()

        XCTAssertEqual(statusAfter.totalFiles, statusBefore.totalFiles + 1)

        // Should now find NetworkManager
        let results = await index.search(query: "NetworkManager fetch")
        XCTAssertFalse(results.isEmpty)
    }

    // MARK: - IndexStatus

    func testIndexStatusEmpty() async {
        let index = SemanticIndex()
        let status = await index.status()
        XCTAssertEqual(status.totalChunks, 0)
        XCTAssertEqual(status.totalTokens, 0)
        XCTAssertEqual(status.totalFiles, 0)
        XCTAssertEqual(status.avgDocLength, 0)
        XCTAssertFalse(status.hasMerkleTree)
    }

    func testIndexStatusAfterBuild() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let status = await index.status()
        XCTAssertGreaterThan(status.totalChunks, 0)
        XCTAssertGreaterThan(status.totalTokens, 0)
        XCTAssertEqual(status.totalFiles, 3)
        XCTAssertGreaterThan(status.avgDocLength, 0)
        XCTAssertTrue(status.hasMerkleTree)
        XCTAssertNotEqual(status.simHash, 0)
    }

    // MARK: - Persistence

    func testPersistAndReload() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistPath = tmpDir.appendingPathComponent("index.jsonl")
        let index = SemanticIndex(persistencePath: persistPath)
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let statusBefore = await index.status()

        // Create a new index and load from disk
        let loaded = SemanticIndex(persistencePath: persistPath)
        await loaded.loadFromDisk()

        let statusAfter = await loaded.status()
        XCTAssertEqual(statusAfter.totalChunks, statusBefore.totalChunks)
        XCTAssertEqual(statusAfter.totalFiles, statusBefore.totalFiles)

        // Search should still work
        let results = await loaded.search(query: "authentication login")
        XCTAssertFalse(results.isEmpty)
    }

    // MARK: - Target Directories Filter

    func testSearchWithTargetDirectories() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-dir-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("Tests"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let srcContent = "class AuthService { func login() {} }"
        let testContent = "class AuthServiceTests: XCTestCase { func testLogin() {} }"

        let srcPath = tmpDir.appendingPathComponent("Sources/AuthService.swift")
        let testPath = tmpDir.appendingPathComponent("Tests/AuthServiceTests.swift")
        try! srcContent.write(to: srcPath, atomically: true, encoding: .utf8)
        try! testContent.write(to: testPath, atomically: true, encoding: .utf8)

        let files = [
            IndexedFile(relativePath: "Sources/AuthService.swift", absolutePath: srcPath.path, language: .swift,
                        symbols: [IndexedSymbol(name: "AuthService", kind: .class, filePath: "Sources/AuthService.swift", line: 1, endLine: 1, language: .swift)],
                        imports: [], lineCount: 1, size: UInt64(srcContent.utf8.count)),
            IndexedFile(relativePath: "Tests/AuthServiceTests.swift", absolutePath: testPath.path, language: .swift,
                        symbols: [IndexedSymbol(name: "AuthServiceTests", kind: .class, filePath: "Tests/AuthServiceTests.swift", line: 1, endLine: 1, language: .swift)],
                        imports: ["XCTest"], lineCount: 1, size: UInt64(testContent.utf8.count)),
        ]

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        // Search only in Sources
        let results = await index.search(query: "auth", targetDirectories: ["Sources"])
        for r in results {
            XCTAssertTrue(r.chunk.filePath.hasPrefix("Sources"))
        }
    }
}
