import Foundation
import XCTest
@testable import CoderEngine

final class CodebaseIndexIncrementalTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codebase-index-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testIncrementalUpdateRemovesDeletedFileFromSymbolAndSemanticIndexes() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let stable = workspace.appendingPathComponent("Stable.swift")
        let deleted = workspace.appendingPathComponent("Deleted.swift")

        try "struct StableType { let value = 1 }\n".write(to: stable, atomically: true, encoding: .utf8)
        try "class GhostType { func removedMethod() {} }\n".write(to: deleted, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let hasGhostSymbolsBeforeDelete = await index.findSymbols(query: "GhostType").isEmpty == false
        let hasDeletedFileBeforeDelete = await index.findFiles(query: "Deleted.swift").isEmpty == false
        XCTAssertTrue(hasGhostSymbolsBeforeDelete)
        XCTAssertTrue(hasDeletedFileBeforeDelete)

        try FileManager.default.removeItem(at: deleted)
        _ = await index.incrementalUpdate()

        let hasGhostSymbolsAfterDelete = await index.findSymbols(query: "GhostType").isEmpty
        let hasDeletedFileAfterDelete = await index.findFiles(query: "Deleted.swift").isEmpty
        XCTAssertTrue(hasGhostSymbolsAfterDelete)
        XCTAssertTrue(hasDeletedFileAfterDelete)

        let semanticResults = await index.semanticIndex.search(
            query: "GhostType removedMethod",
            targetDirectories: [],
            numResults: 20
        )
        XCTAssertFalse(semanticResults.contains { $0.chunk.filePath.contains("Deleted.swift") })
    }

    func testRemoveSingleFileRemovesRealtimeEntriesImmediately() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("Realtime.swift")
        try "final class RealtimeDelete { func ping() {} }\n".write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let hasRealtimeSymbolBeforeDelete = await index.findSymbols(query: "RealtimeDelete").isEmpty == false
        XCTAssertTrue(hasRealtimeSymbolBeforeDelete)

        await index.removeSingleFile(absolutePath: file.path)

        let hasRealtimeSymbolAfterDelete = await index.findSymbols(query: "RealtimeDelete").isEmpty
        XCTAssertTrue(hasRealtimeSymbolAfterDelete)

        let semanticResults = await index.semanticIndex.search(
            query: "RealtimeDelete ping",
            targetDirectories: [],
            numResults: 10
        )
        XCTAssertTrue(semanticResults.isEmpty)
    }

    func testRealtimeUpdateQueuedDuringWorkspaceRebuildIsAppliedAfterCompletion() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        for i in 0..<220 {
            try "struct Seed\(i) { let value = \(i) }\n".write(
                to: workspace.appendingPathComponent("Seed\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        let queuedFile = workspace.appendingPathComponent("QueuedRealtime.swift")
        try "final class QueuedRealtime { func ping() {} }\n".write(
            to: queuedFile,
            atomically: true,
            encoding: .utf8
        )

        let index = CodebaseIndex()
        let indexingTask = Task { await index.indexWorkspace(paths: [workspace]) }

        var sawIndexing = false
        for _ in 0..<50 {
            let status = await index.status()
            if status.status == .indexing {
                sawIndexing = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(sawIndexing, "Expected workspace rebuild to enter indexing state")

        await index.indexSingleFile(absolutePath: queuedFile.path, relativePath: "QueuedRealtime.swift")
        _ = await indexingTask.value

        let symbolResults = await index.findSymbols(query: "QueuedRealtime")
        XCTAssertFalse(symbolResults.isEmpty, "Queued realtime update should be flushed after rebuild")
    }
}
