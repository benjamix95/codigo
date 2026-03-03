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

    func testLoadFromDiskRejectsInvalidSchemaMetadata() async throws {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistPath = tmpDir.appendingPathComponent("index.jsonl")
        let index = SemanticIndex(persistencePath: persistPath)
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let metaPath = tmpDir.appendingPathComponent("semantic.meta.json")
        let invalidMeta = """
        {
          "version": 2,
          "schema": "broken_schema",
          "simHash": 123,
          "totalChunks": 999,
          "totalFiles": 1
        }
        """
        try invalidMeta.write(to: metaPath, atomically: true, encoding: .utf8)

        let loaded = SemanticIndex(persistencePath: persistPath)
        await loaded.loadFromDisk()
        let statusAfter = await loaded.status()
        XCTAssertEqual(statusAfter.totalChunks, 0)
        XCTAssertEqual(statusAfter.totalFiles, 0)
    }

    func testLoadFromDiskPreservesAllChunksPerFileForRemoval() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-persist-chunks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let content = """
        struct MultiChunkProbe {
            func firstSection() {
                let a = 1
                let b = 2
                let c = a + b
                print(c)
            }

            func secondSection() {
                let x = "alpha"
                let y = "beta"
                let z = x + y
                print(z)
            }
        }
        """
        let fileURL = tmpDir.appendingPathComponent("MultiChunkProbe.swift")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let indexed = IndexedFile(
            relativePath: "MultiChunkProbe.swift",
            absolutePath: fileURL.path,
            language: .swift,
            symbols: [
                IndexedSymbol(name: "firstSection", kind: .method, filePath: "MultiChunkProbe.swift", line: 2, endLine: 7, containerName: "MultiChunkProbe", language: .swift),
                IndexedSymbol(name: "secondSection", kind: .method, filePath: "MultiChunkProbe.swift", line: 9, endLine: 14, containerName: "MultiChunkProbe", language: .swift),
            ],
            imports: [],
            lineCount: content.components(separatedBy: "\n").count,
            size: UInt64(content.utf8.count)
        )

        let persistPath = tmpDir.appendingPathComponent("semantic.jsonl")
        let index = SemanticIndex(persistencePath: persistPath)
        await index.buildIndex(indexedFiles: [indexed], workspaceRoot: tmpDir)

        let loaded = SemanticIndex(persistencePath: persistPath)
        await loaded.loadFromDisk()
        await loaded.removeFile("MultiChunkProbe.swift")

        let status = await loaded.status()
        let results = await loaded.search(query: "firstSection secondSection")
        XCTAssertEqual(status.totalFiles, 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testPersistWritesDeterministicChunkOrder() async throws {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistPath = tmpDir.appendingPathComponent("deterministic.jsonl")
        let index = SemanticIndex(persistencePath: persistPath)
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)
        let firstSnapshot = try String(contentsOf: persistPath, encoding: .utf8)

        await index.buildIndex(indexedFiles: files.reversed(), workspaceRoot: tmpDir)
        let secondSnapshot = try String(contentsOf: persistPath, encoding: .utf8)

        XCTAssertEqual(firstSnapshot, secondSnapshot)
    }

    func testLoadFromDiskRejectsTokenizerFingerprintMismatch() async throws {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistPath = tmpDir.appendingPathComponent("fingerprint.jsonl")
        let index = SemanticIndex(persistencePath: persistPath)
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let metaPath = tmpDir.appendingPathComponent("semantic.meta.json")
        var meta = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: metaPath), options: []) as? [String: Any]
        )
        meta["synonymsFingerprint"] = "deadbeef"
        let tamperedData = try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
        try tamperedData.write(to: metaPath, options: .atomic)

        let loaded = SemanticIndex(persistencePath: persistPath)
        await loaded.loadFromDisk()

        let status = await loaded.status()
        XCTAssertEqual(status.totalChunks, 0)
        XCTAssertEqual(status.totalFiles, 0)
    }

    func testBuildIndexReadsNonUTF8ContentWithFallbackEncoding() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-encoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("Latin1.swift")
        let latin1Data = Data([0x54, 0x6F, 0x6B, 0x65, 0x6E, 0x4C, 0x61, 0x74, 0x69, 0x6E, 0x31, 0x20, 0x3D, 0x20, 0xE9])
        try latin1Data.write(to: fileURL, options: .atomic)

        let indexed = IndexedFile(
            relativePath: "Latin1.swift",
            absolutePath: fileURL.path,
            language: .swift,
            symbols: [],
            imports: [],
            lineCount: 1,
            size: UInt64(latin1Data.count)
        )
        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: [indexed], workspaceRoot: tmpDir)

        let results = await index.search(query: "TokenLatin1", numResults: 5)
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
