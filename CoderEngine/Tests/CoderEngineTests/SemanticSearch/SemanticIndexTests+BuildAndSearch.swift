import Foundation
import XCTest
@testable import CoderEngine

extension SemanticIndexTests {

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
}
