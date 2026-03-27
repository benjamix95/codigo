import XCTest
@testable import CoderEngine

final class CodebaseIndexFullIndexOptimizationTests: XCTestCase {
    private final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    func testBuildIndexUsesProvidedContentCacheWithoutDiskReads() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-cache-opt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fileURL = workspace.appendingPathComponent("Probe.swift")
        try """
        struct Probe {
            func authFlow() {
                print("probe")
            }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let indexed = try XCTUnwrap(
            SymbolExtractor.indexFileWithContent(
                absolutePath: fileURL.path,
                relativePath: "Probe.swift",
                language: .swift
            )
        )
        let prebuiltMerkleRoot = MerkleTree.build(
            indexedFiles: [indexed.file],
            contentCache: [indexed.file.absolutePath: indexed.content],
            workspaceRoot: workspace
        )
        let semanticIndex = SemanticIndex()
        let counter = ReadCounter()
        SemanticIndex.readTextFileObserver = { _ in counter.increment() }
        defer { SemanticIndex.readTextFileObserver = nil }

        await semanticIndex.buildIndex(
            indexedFiles: [indexed.file],
            workspaceRoot: workspace,
            contentCache: [indexed.file.absolutePath: indexed.content],
            prebuiltMerkleRoot: prebuiltMerkleRoot
        )

        XCTAssertEqual(counter.value, 0, "Expected buildIndex to reuse provided content cache")
        let status = await semanticIndex.status()
        XCTAssertEqual(status.totalChunks, 1)
    }
}
