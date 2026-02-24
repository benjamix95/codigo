import XCTest
@testable import CoderEngine

// MARK: - SemanticChunkerTests

final class SemanticChunkerTests: XCTestCase {

    // MARK: - Helpers

    private func makeSymbol(
        name: String,
        kind: SymbolKind,
        filePath: String = "test.swift",
        line: Int,
        endLine: Int = 0,
        containerName: String? = nil
    ) -> IndexedSymbol {
        IndexedSymbol(
            name: name, kind: kind, filePath: filePath,
            line: line, endLine: endLine, containerName: containerName,
            language: .swift
        )
    }

    private func makeIndexedFile(
        relativePath: String = "Sources/App/Service.swift",
        absolutePath: String = "/tmp/Sources/App/Service.swift",
        symbols: [IndexedSymbol] = [],
        imports: [String] = ["Foundation"],
        content: String
    ) -> IndexedFile {
        IndexedFile(
            relativePath: relativePath,
            absolutePath: absolutePath,
            language: .swift,
            symbols: symbols,
            imports: imports,
            lineCount: content.components(separatedBy: "\n").count,
            size: UInt64(content.utf8.count)
        )
    }

    // MARK: - Chunk ID Format

    func testChunkIdFormat() {
        let chunk = SemanticChunk(
            filePath: "Sources/App.swift",
            startLine: 10,
            endLine: 25,
            content: "func test() {}",
            scope: "App",
            kind: "function",
            language: "swift"
        )
        XCTAssertEqual(chunk.id, "Sources/App.swift:10:25")
    }

    // MARK: - ContentWeight

    func testContentWeightExcludesWhitespace() {
        let chunk = SemanticChunk(
            filePath: "test.swift",
            startLine: 1, endLine: 1,
            content: "   hello   world   ",
            scope: "", kind: "block", language: "swift"
        )
        XCTAssertEqual(chunk.contentWeight, 10) // "helloworld"
    }

    // MARK: - ContextualizedText

    func testContextualizedTextIncludesMetadata() {
        let chunk = SemanticChunk(
            filePath: "Sources/Auth.swift",
            startLine: 5, endLine: 20,
            content: "class AuthService { }",
            scope: "AuthService",
            kind: "class",
            language: "swift",
            symbolNames: ["AuthService"],
            imports: ["Foundation", "CryptoKit"]
        )
        let text = chunk.contextualizedText
        XCTAssertTrue(text.contains("# Sources/Auth.swift"))
        XCTAssertTrue(text.contains("# Scope: AuthService"))
        XCTAssertTrue(text.contains("# Defines: AuthService"))
        XCTAssertTrue(text.contains("# Uses: Foundation, CryptoKit"))
        XCTAssertTrue(text.contains("class AuthService { }"))
    }

    func testContextualizedTextOmitsEmptyFields() {
        let chunk = SemanticChunk(
            filePath: "test.swift",
            startLine: 1, endLine: 5,
            content: "let x = 1",
            scope: "", kind: "block", language: "swift"
        )
        let text = chunk.contextualizedText
        XCTAssertTrue(text.contains("# test.swift"))
        XCTAssertFalse(text.contains("# Scope:"))
        XCTAssertFalse(text.contains("# Defines:"))
        XCTAssertFalse(text.contains("# Uses:"))
    }

    // MARK: - Chunking with Symbols

    func testChunkingWithSymbolBoundaries() {
        let content = """
        import Foundation

        class UserService {
            func getUser(id: String) -> User {
                return db.find(id)
            }

            func saveUser(_ user: User) {
                db.save(user)
            }
        }
        """

        let symbols = [
            makeSymbol(name: "UserService", kind: .class, line: 3, endLine: 11),
            makeSymbol(name: "getUser", kind: .method, line: 4, endLine: 6, containerName: "UserService"),
            makeSymbol(name: "saveUser", kind: .method, line: 8, endLine: 10, containerName: "UserService")
        ]

        let file = makeIndexedFile(symbols: symbols, content: content)
        let chunks = SemanticChunker.chunk(indexedFile: file, fileContent: content)

        // Should produce at least 1 chunk
        XCTAssertFalse(chunks.isEmpty)
        // All chunks should have valid line ranges
        for chunk in chunks {
            XCTAssertGreaterThanOrEqual(chunk.startLine, 1)
            XCTAssertGreaterThanOrEqual(chunk.endLine, chunk.startLine)
        }
    }

    func testChunkingWithNoSymbolsCreatesSingleChunk() {
        let content = """
        // Just a plain file with no symbols
        let x = 1
        let y = 2
        print(x + y)
        """

        let file = makeIndexedFile(symbols: [], content: content)
        let chunks = SemanticChunker.chunk(indexedFile: file, fileContent: content)

        // With no symbols, should create at most 1 chunk (if content weight >= minimum)
        XCTAssertLessThanOrEqual(chunks.count, 1)
    }

    func testChunkingRespectsSizeLimits() {
        // Create a very long file
        var lines: [String] = ["import Foundation\n"]
        for i in 0..<500 {
            lines.append("func method\(i)() { print(\"line \(i)\") }")
        }
        let content = lines.joined(separator: "\n")

        var symbols: [IndexedSymbol] = []
        for i in 0..<500 {
            symbols.append(makeSymbol(name: "method\(i)", kind: .function, line: i + 2))
        }

        let file = makeIndexedFile(symbols: symbols, content: content)
        let chunks = SemanticChunker.chunk(indexedFile: file, fileContent: content)

        // No chunk should exceed maxChunkLines
        for chunk in chunks {
            let lineCount = chunk.endLine - chunk.startLine + 1
            XCTAssertLessThanOrEqual(lineCount, SemanticChunker.maxChunkLines)
        }
    }

    func testChunkingFiltersSmallFragments() {
        // A file where each symbol region is very small
        let content = """
        let a = 1
        """

        let symbols = [makeSymbol(name: "a", kind: .variable, line: 1)]
        let file = makeIndexedFile(symbols: symbols, content: content)
        let chunks = SemanticChunker.chunk(indexedFile: file, fileContent: content)

        // Should filter out chunks below minChunkWeight
        for chunk in chunks {
            XCTAssertGreaterThanOrEqual(chunk.contentWeight, SemanticChunker.minChunkWeight)
        }
    }

    // MARK: - Raw File Chunking

    func testChunkRawFileProducesChunks() {
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("print(\"line \(i) with some meaningful content for chunking\")")
        }
        let content = lines.joined(separator: "\n")

        let chunks = SemanticChunker.chunkRawFile(
            filePath: "test.py",
            content: content,
            language: "python"
        )

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.first?.language, "python")
        XCTAssertEqual(chunks.first?.filePath, "test.py")
    }

    func testChunkRawFileEmptyContent() {
        let chunks = SemanticChunker.chunkRawFile(filePath: "empty.swift", content: "", language: "swift")
        XCTAssertTrue(chunks.isEmpty)
    }

    // MARK: - Chunk Scope

    func testChunkContainsCorrectScope() {
        let content = """
        import Foundation

        class MyClass {
            func myMethod() {
                print("hello")
            }
        }
        """

        let symbols = [
            makeSymbol(name: "MyClass", kind: .class, line: 3, endLine: 7),
            makeSymbol(name: "myMethod", kind: .method, line: 4, endLine: 6, containerName: "MyClass")
        ]

        let file = makeIndexedFile(symbols: symbols, content: content)
        let chunks = SemanticChunker.chunk(indexedFile: file, fileContent: content)

        // At least one chunk should have scope info
        let hasScope = chunks.contains { !$0.scope.isEmpty }
        XCTAssertTrue(hasScope)
    }
}

// MARK: - MerkleTreeTests

final class MerkleTreeTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("merkle-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Build

    func testBuildFromEmptyDirectory() {
        // Empty dir should return nil (no files)
        let node = MerkleTree.build(root: tmpDir)
        XCTAssertNil(node)
    }

    func testBuildFromDirectoryWithFiles() throws {
        // Create some Swift files
        try "func hello() {}".write(
            to: tmpDir.appendingPathComponent("main.swift"),
            atomically: true, encoding: .utf8
        )
        try "struct User {}".write(
            to: tmpDir.appendingPathComponent("model.swift"),
            atomically: true, encoding: .utf8
        )

        let node = MerkleTree.build(root: tmpDir)
        XCTAssertNotNil(node)
        XCTAssertTrue(node!.isDirectory)
        XCTAssertEqual(node!.children.count, 2)
        XCTAssertFalse(node!.hash.isEmpty)
        XCTAssertEqual(node!.hash.count, 64) // SHA-256 hex = 64 chars
    }

    func testBuildExcludesHiddenDirs() throws {
        let hiddenDir = tmpDir.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "secret".write(to: hiddenDir.appendingPathComponent("secret.swift"), atomically: true, encoding: .utf8)
        try "public".write(to: tmpDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let node = MerkleTree.build(root: tmpDir)
        XCTAssertNotNil(node)
        // Should only have 1 child (main.swift), not the hidden dir
        XCTAssertEqual(node!.children.count, 1)
        XCTAssertEqual(node!.children[0].path, "main.swift")
    }

    func testBuildExcludesNodeModules() throws {
        let nm = tmpDir.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try "module".write(to: nm.appendingPathComponent("package.js"), atomically: true, encoding: .utf8)
        try "public".write(to: tmpDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

        let node = MerkleTree.build(root: tmpDir)
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.children.count, 1)
    }

    func testBuildFiltersExtensions() throws {
        try "binary".write(to: tmpDir.appendingPathComponent("data.bin"), atomically: true, encoding: .utf8)
        try "code".write(to: tmpDir.appendingPathComponent("app.swift"), atomically: true, encoding: .utf8)

        let node = MerkleTree.build(root: tmpDir)
        XCTAssertNotNil(node)
        // Only .swift should be included
        XCTAssertEqual(node!.children.count, 1)
        XCTAssertEqual(node!.children[0].path, "app.swift")
    }

    // MARK: - Hashing

    func testFileHashIsDeterministic() throws {
        try "func hello() {}".write(to: tmpDir.appendingPathComponent("test.swift"), atomically: true, encoding: .utf8)
        let node1 = MerkleTree.build(root: tmpDir)
        let node2 = MerkleTree.build(root: tmpDir)

        XCTAssertNotNil(node1)
        XCTAssertNotNil(node2)
        XCTAssertEqual(node1!.hash, node2!.hash)
    }

    func testFileHashChangesWhenContentChanges() throws {
        let file = tmpDir.appendingPathComponent("test.swift")
        try "func hello() {}".write(to: file, atomically: true, encoding: .utf8)
        let node1 = MerkleTree.build(root: tmpDir)

        try "func world() {}".write(to: file, atomically: true, encoding: .utf8)
        let node2 = MerkleTree.build(root: tmpDir)

        XCTAssertNotNil(node1)
        XCTAssertNotNil(node2)
        XCTAssertNotEqual(node1!.hash, node2!.hash)
    }

    // MARK: - Diff

    func testDiffDetectsAddedFile() throws {
        try "original".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let old = MerkleTree.build(root: tmpDir)

        try "new file".write(to: tmpDir.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
        let new = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: old, new: new)
        XCTAssertTrue(diff.added.contains("b.swift"))
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testDiffDetectsRemovedFile() throws {
        try "file a".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "file b".write(to: tmpDir.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
        let old = MerkleTree.build(root: tmpDir)

        try FileManager.default.removeItem(at: tmpDir.appendingPathComponent("b.swift"))
        let new = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: old, new: new)
        XCTAssertTrue(diff.removed.contains("b.swift"))
        XCTAssertTrue(diff.added.isEmpty)
    }

    func testDiffDetectsModifiedFile() throws {
        let file = tmpDir.appendingPathComponent("a.swift")
        try "version 1".write(to: file, atomically: true, encoding: .utf8)
        let old = MerkleTree.build(root: tmpDir)

        try "version 2".write(to: file, atomically: true, encoding: .utf8)
        let new = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: old, new: new)
        XCTAssertTrue(diff.modified.contains("a.swift"))
    }

    func testDiffNilOldReportsAllAsAdded() throws {
        try "new content".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let new = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: nil, new: new)
        XCTAssertFalse(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testDiffNilNewReportsAllAsRemoved() throws {
        try "old content".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let old = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: old, new: nil)
        XCTAssertFalse(diff.removed.isEmpty)
        XCTAssertTrue(diff.added.isEmpty)
    }

    func testDiffIdenticalTreesIsEmpty() throws {
        try "same content".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let tree = MerkleTree.build(root: tmpDir)

        let diff = MerkleTree.diff(old: tree, new: tree)
        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.totalChanges, 0)
    }

    // MARK: - SimHash

    func testSimHashDeterministic() throws {
        try "func test() {}".write(to: tmpDir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let node = MerkleTree.build(root: tmpDir)!

        let hash1 = MerkleTree.simHash(of: node)
        let hash2 = MerkleTree.simHash(of: node)
        XCTAssertEqual(hash1, hash2)
    }

    func testSimHashSimilarCodebasesProduceSimilarHashes() throws {
        // Create workspace A
        let dirA = tmpDir.appendingPathComponent("A", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try "func hello() {}".write(to: dirA.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "struct User {}".write(to: dirA.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
        let nodeA = MerkleTree.build(root: dirA)!

        // Create workspace B (same files + 1 extra)
        let dirB = tmpDir.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try "func hello() {}".write(to: dirB.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "struct User {}".write(to: dirB.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
        try "enum Color {}".write(to: dirB.appendingPathComponent("c.swift"), atomically: true, encoding: .utf8)
        let nodeB = MerkleTree.build(root: dirB)!

        let hashA = MerkleTree.simHash(of: nodeA)
        let hashB = MerkleTree.simHash(of: nodeB)
        let sim = MerkleTree.similarity(hashA, hashB)

        // Similar codebases should have high similarity
        XCTAssertGreaterThan(sim, 0.5)
    }

    func testHammingDistanceOfIdentical() {
        let d = MerkleTree.hammingDistance(0xABCD1234, 0xABCD1234)
        XCTAssertEqual(d, 0)
    }

    func testHammingDistanceOfOpposites() {
        let d = MerkleTree.hammingDistance(0, UInt64.max)
        XCTAssertEqual(d, 64)
    }

    func testSimilarityOfIdentical() {
        let s = MerkleTree.similarity(42, 42)
        XCTAssertEqual(s, 1.0)
    }

    func testSimilarityOfOpposites() {
        let s = MerkleTree.similarity(0, UInt64.max)
        XCTAssertEqual(s, 0.0)
    }

    // MARK: - ChangeSummary

    func testChangeSummaryProperties() {
        let summary = MerkleTree.ChangeSummary(
            added: ["a.swift", "b.swift"],
            removed: ["c.swift"],
            modified: ["d.swift"]
        )
        XCTAssertEqual(summary.totalChanges, 4)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.changedPaths.count, 4)
    }

    func testChangeSummaryEmpty() {
        let summary = MerkleTree.ChangeSummary(added: [], removed: [], modified: [])
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.totalChanges, 0)
    }
}

// MARK: - SemanticIndexTests

final class SemanticIndexTests: XCTestCase {

    // MARK: - Helpers

    private func makeTestIndexedFiles() -> ([IndexedFile], URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-index-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let content1 = """
        import Foundation

        class AuthenticationService {
            func login(username: String, password: String) -> Bool {
                return validateCredentials(username, password)
            }

            func logout() {
                clearSession()
            }

            private func validateCredentials(_ user: String, _ pass: String) -> Bool {
                return true
            }

            private func clearSession() { }
        }
        """

        let content2 = """
        import Foundation

        struct UserProfile {
            let id: String
            let name: String
            let email: String

            func save() {
                Database.shared.persist(self)
            }

            func delete() {
                Database.shared.remove(id)
            }
        }
        """

        let content3 = """
        import XCTest

        final class AuthTests: XCTestCase {
            func testLoginSuccess() {
                let service = AuthenticationService()
                XCTAssertTrue(service.login(username: "admin", password: "pass"))
            }

            func testLogoutClearsSession() {
                let service = AuthenticationService()
                service.logout()
            }
        }
        """

        let file1Path = tmpDir.appendingPathComponent("AuthenticationService.swift")
        let file2Path = tmpDir.appendingPathComponent("UserProfile.swift")
        let file3Path = tmpDir.appendingPathComponent("AuthTests.swift")

        try! content1.write(to: file1Path, atomically: true, encoding: .utf8)
        try! content2.write(to: file2Path, atomically: true, encoding: .utf8)
        try! content3.write(to: file3Path, atomically: true, encoding: .utf8)

        let sym1 = [
            IndexedSymbol(name: "AuthenticationService", kind: .class, filePath: "AuthenticationService.swift", line: 3, endLine: 17, language: .swift),
            IndexedSymbol(name: "login", kind: .method, filePath: "AuthenticationService.swift", line: 4, endLine: 6, containerName: "AuthenticationService", language: .swift),
            IndexedSymbol(name: "logout", kind: .method, filePath: "AuthenticationService.swift", line: 8, endLine: 10, containerName: "AuthenticationService", language: .swift),
        ]

        let sym2 = [
            IndexedSymbol(name: "UserProfile", kind: .struct, filePath: "UserProfile.swift", line: 3, endLine: 15, language: .swift),
            IndexedSymbol(name: "save", kind: .method, filePath: "UserProfile.swift", line: 8, endLine: 10, containerName: "UserProfile", language: .swift),
            IndexedSymbol(name: "delete", kind: .method, filePath: "UserProfile.swift", line: 12, endLine: 14, containerName: "UserProfile", language: .swift),
        ]

        let sym3 = [
            IndexedSymbol(name: "AuthTests", kind: .class, filePath: "AuthTests.swift", line: 3, endLine: 13, language: .swift),
            IndexedSymbol(name: "testLoginSuccess", kind: .test, filePath: "AuthTests.swift", line: 4, endLine: 7, containerName: "AuthTests", language: .swift),
            IndexedSymbol(name: "testLogoutClearsSession", kind: .test, filePath: "AuthTests.swift", line: 9, endLine: 12, containerName: "AuthTests", language: .swift),
        ]

        let files = [
            IndexedFile(relativePath: "AuthenticationService.swift", absolutePath: file1Path.path, language: .swift, symbols: sym1, imports: ["Foundation"], lineCount: 18, size: UInt64(content1.utf8.count)),
            IndexedFile(relativePath: "UserProfile.swift", absolutePath: file2Path.path, language: .swift, symbols: sym2, imports: ["Foundation"], lineCount: 16, size: UInt64(content2.utf8.count)),
            IndexedFile(relativePath: "AuthTests.swift", absolutePath: file3Path.path, language: .swift, symbols: sym3, imports: ["XCTest"], lineCount: 14, size: UInt64(content3.utf8.count)),
        ]

        return (files, tmpDir)
    }

    // MARK: - Build Index

    func testBuildIndexPopulatesChunks() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let status = await index.status()
        XCTAssertGreaterThan(status.totalChunks, 0)
        XCTAssertGreaterThan(status.totalTokens, 0)
        XCTAssertEqual(status.totalFiles, 3)
        XCTAssertGreaterThan(status.avgDocLength, 0)
    }

    // MARK: - Search

    func testSearchByExactSymbolName() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let results = await index.search(query: "AuthenticationService")
        XCTAssertFalse(results.isEmpty)
        // First result should be from the auth file
        XCTAssertTrue(results[0].chunk.filePath.contains("Auth"))
    }

    func testSearchBySynonym() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        // "auth" should match AuthenticationService via synonym expansion (auth→authentication, login, signin)
        let results = await index.search(query: "auth login flow")
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchByMeaning() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        // "save data" should find UserProfile.save() via synonym (save→persist, store)
        let results = await index.search(query: "save data")
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchRespectsNumResults() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let results = await index.search(query: "function", numResults: 2)
        XCTAssertLessThanOrEqual(results.count, 2)
    }

    func testSearchNoResults() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let results = await index.search(query: "zzzzxxxxyyyy_nonexistent_term")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchEmptyQuery() async {
        let index = SemanticIndex()
        let results = await index.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchResultsAreRankedByScore() async {
        let (files, tmpDir) = makeTestIndexedFiles()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let results = await index.search(query: "authentication login")
        guard results.count >= 2 else {
            // Not enough results to check ranking, skip
            return
        }
        // Results should be in descending score order
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score)
        }
    }

    // MARK: - SearchResult Display

    func testSearchResultDisplayLine() {
        let chunk = SemanticChunk(
            filePath: "Sources/Auth.swift",
            startLine: 10, endLine: 25,
            content: "func login() {}",
            scope: "AuthService",
            kind: "function",
            language: "swift"
        )
        let result = SemanticIndex.SearchResult(chunk: chunk, score: 5.42)
        XCTAssertTrue(result.displayLine.contains("Sources/Auth.swift"))
        XCTAssertTrue(result.displayLine.contains(":10-25"))
        XCTAssertTrue(result.displayLine.contains("[AuthService]"))
        XCTAssertTrue(result.displayLine.contains("5.42"))
    }

    func testSearchResultDisplayLineSingleLine() {
        let chunk = SemanticChunk(
            filePath: "test.swift",
            startLine: 5, endLine: 5,
            content: "let x = 1",
            scope: "",
            kind: "variable",
            language: "swift"
        )
        let result = SemanticIndex.SearchResult(chunk: chunk, score: 1.0)
        XCTAssertTrue(result.displayLine.contains(":5"))
        XCTAssertFalse(result.displayLine.contains("-"))
    }

    // MARK: - Tokenization

    func testTokenizeCamelCase() {
        let tokens = SemanticIndex.tokenizeStatic("handleUserLogin")
        XCTAssertTrue(tokens.contains("handle"))
        XCTAssertTrue(tokens.contains("user"))
        XCTAssertTrue(tokens.contains("login"))
        XCTAssertTrue(tokens.contains("handleuserlogin"))
    }

    func testTokenizeSnakeCase() {
        let tokens = SemanticIndex.tokenizeStatic("handle_user_login")
        XCTAssertTrue(tokens.contains("handle"))
        XCTAssertTrue(tokens.contains("user"))
        XCTAssertTrue(tokens.contains("login"))
    }

    func testTokenizeRemovesStopwords() {
        let tokens = SemanticIndex.tokenizeStatic("the public var is static")
        // "the", "is", "var", "public", "static" are all stopwords
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("var"))
        XCTAssertFalse(tokens.contains("public"))
        XCTAssertFalse(tokens.contains("static"))
    }

    func testTokenizeSynonymExpansion() {
        let tokens = SemanticIndex.tokenizeStatic("auth")
        // "auth" should expand to include authentication, login, etc.
        XCTAssertTrue(tokens.contains("auth"))
        XCTAssertTrue(tokens.contains("authentication") || tokens.contains("login") || tokens.contains("signin"))
    }

    func testTokenizeShortWordsFiltered() {
        let tokens = SemanticIndex.tokenizeStatic("a b c de fg")
        // Single char words should be filtered (< 2 chars)
        XCTAssertFalse(tokens.contains("a"))
        XCTAssertFalse(tokens.contains("b"))
        XCTAssertFalse(tokens.contains("c"))
        XCTAssertTrue(tokens.contains("de"))
        XCTAssertTrue(tokens.contains("fg"))
    }

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
