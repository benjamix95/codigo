import Foundation
import XCTest
@testable import CoderEngine

final class SemanticChunkerTests: XCTestCase {}

extension SemanticChunkerTests {

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
