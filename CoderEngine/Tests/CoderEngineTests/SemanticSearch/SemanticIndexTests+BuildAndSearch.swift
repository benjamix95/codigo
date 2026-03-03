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

    func testSearchNaturalLanguageRanksAuthHandlerBeforeGenericHandler() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-nl-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let authContent = """
        final class AuthenticationCoordinator {
            func handleAuthenticationRequest(token: String) -> Bool {
                authorizeUser(token)
            }

            private func authorizeUser(_ token: String) -> Bool { !token.isEmpty }
        }
        """
        let genericContent = """
        struct GenericRequestHandler {
            func handleRequest(_ payload: String) -> Bool {
                !payload.isEmpty
            }
        }
        """

        let authPath = tmpDir.appendingPathComponent("AuthenticationCoordinator.swift")
        let genericPath = tmpDir.appendingPathComponent("GenericRequestHandler.swift")
        try authContent.write(to: authPath, atomically: true, encoding: .utf8)
        try genericContent.write(to: genericPath, atomically: true, encoding: .utf8)

        let files = [
            IndexedFile(
                relativePath: "AuthenticationCoordinator.swift",
                absolutePath: authPath.path,
                language: .swift,
                symbols: [
                    IndexedSymbol(name: "AuthenticationCoordinator", kind: .class, filePath: "AuthenticationCoordinator.swift", line: 1, endLine: 7, language: .swift),
                    IndexedSymbol(name: "handleAuthenticationRequest", kind: .method, filePath: "AuthenticationCoordinator.swift", line: 2, endLine: 4, containerName: "AuthenticationCoordinator", language: .swift),
                    IndexedSymbol(name: "authorizeUser", kind: .method, filePath: "AuthenticationCoordinator.swift", line: 6, endLine: 6, containerName: "AuthenticationCoordinator", language: .swift),
                ],
                imports: [],
                lineCount: 7,
                size: UInt64(authContent.utf8.count)
            ),
            IndexedFile(
                relativePath: "GenericRequestHandler.swift",
                absolutePath: genericPath.path,
                language: .swift,
                symbols: [
                    IndexedSymbol(name: "GenericRequestHandler", kind: .struct, filePath: "GenericRequestHandler.swift", line: 1, endLine: 5, language: .swift),
                    IndexedSymbol(name: "handleRequest", kind: .method, filePath: "GenericRequestHandler.swift", line: 2, endLine: 4, containerName: "GenericRequestHandler", language: .swift),
                ],
                imports: [],
                lineCount: 5,
                size: UInt64(genericContent.utf8.count)
            ),
        ]

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        let results = await index.search(query: "where is auth handled", numResults: 5)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.chunk.filePath, "AuthenticationCoordinator.swift")
    }

    func testSearchSynonymsAuthAuthenticationAuthorizeHitSameAuthArea() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-auth-synonyms-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let authContent = """
        enum AuthGateway {
            static func authenticateUser() -> Bool { true }
        }
        """
        let authPath = tmpDir.appendingPathComponent("AuthGateway.swift")
        try authContent.write(to: authPath, atomically: true, encoding: .utf8)

        let files = [
            IndexedFile(
                relativePath: "AuthGateway.swift",
                absolutePath: authPath.path,
                language: .swift,
                symbols: [
                    IndexedSymbol(name: "AuthGateway", kind: .enum, filePath: "AuthGateway.swift", line: 1, endLine: 3, language: .swift),
                    IndexedSymbol(name: "authenticateUser", kind: .method, filePath: "AuthGateway.swift", line: 2, endLine: 2, containerName: "AuthGateway", language: .swift),
                ],
                imports: [],
                lineCount: 3,
                size: UInt64(authContent.utf8.count)
            ),
        ]

        let index = SemanticIndex()
        await index.buildIndex(indexedFiles: files, workspaceRoot: tmpDir)

        for query in ["auth flow", "authentication flow", "authorize flow"] {
            let results = await index.search(query: query, numResults: 3)
            XCTAssertFalse(results.isEmpty, "Query '\(query)' should produce results")
            XCTAssertEqual(results.first?.chunk.filePath, "AuthGateway.swift", "Query '\(query)' should rank auth file first")
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
