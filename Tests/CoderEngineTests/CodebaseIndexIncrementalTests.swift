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

    func testIndexSingleFileWithDisappearedFileRemovesStaleSemanticChunk() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("Transient.swift")
        try "struct TransientType { func ping() {} }\n".write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        try FileManager.default.removeItem(at: file)
        await index.indexSingleFile(absolutePath: file.path, relativePath: "Transient.swift")

        let semanticResults = await index.semanticIndex.search(
            query: "TransientType ping",
            targetDirectories: [],
            numResults: 10
        )
        XCTAssertTrue(semanticResults.isEmpty)
    }

    func testIncrementalUpdateRespectsExcludedPaths() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let ignoredDir = workspace.appendingPathComponent("Ignored", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredDir, withIntermediateDirectories: true)

        let ignoredFile = ignoredDir.appendingPathComponent("Hidden.swift")
        let keptFile = workspace.appendingPathComponent("Visible.swift")
        try "struct HiddenType {}\n".write(to: ignoredFile, atomically: true, encoding: .utf8)
        try "struct VisibleType {}\n".write(to: keptFile, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace], excludedPaths: ["Ignored"])
        try "struct HiddenType { let v = 2 }\n".write(to: ignoredFile, atomically: true, encoding: .utf8)
        _ = await index.incrementalUpdate()

        let hiddenSymbols = await index.findSymbols(query: "HiddenType")
        let visibleSymbols = await index.findSymbols(query: "VisibleType")
        XCTAssertTrue(hiddenSymbols.isEmpty, "Excluded path should remain excluded during incremental update")
        XCTAssertFalse(visibleSymbols.isEmpty)
    }

    func testDuplicateSymbolIDsDoNotInflateCounters() async {
        let index = CodebaseIndex()
        let duplicate = IndexedSymbol(name: "Dup", kind: .class, filePath: "Dup.swift", line: 1, endLine: 1, language: .swift)
        let indexed = IndexedFile(
            relativePath: "Dup.swift",
            absolutePath: "/tmp/Dup.swift",
            language: .swift,
            symbols: [duplicate, duplicate],
            imports: [],
            lineCount: 1,
            size: 10
        )

        await index.addIndexedFile(indexed)
        let status = await index.status()
        XCTAssertEqual(status.totalSymbols, 1)
    }

    func testReaddingIndexedFileDoesNotDuplicateStoredSymbols() async {
        let index = CodebaseIndex()
        let symbol = IndexedSymbol(name: "Stable", kind: .class, filePath: "Stable.swift", line: 1, endLine: 1, language: .swift)
        let indexed = IndexedFile(
            relativePath: "Stable.swift",
            absolutePath: "/tmp/Stable.swift",
            language: .swift,
            symbols: [symbol],
            imports: [],
            lineCount: 1,
            size: 10
        )

        await index.addIndexedFile(indexed)
        await index.addIndexedFile(indexed)

        let status = await index.status()
        let symbols = await index.findSymbols(query: "Stable")
        XCTAssertEqual(status.totalSymbols, 1)
        XCTAssertEqual(symbols.count, 1)
    }

    func testIndexSingleFileNonIndexableExtensionDoesNotCreateSymbolOrSemanticEntries() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let txtFile = workspace.appendingPathComponent("Notes.txt")
        try "TransientType".write(to: txtFile, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        await index.indexSingleFile(absolutePath: txtFile.path, relativePath: "Notes.txt")

        let symbols = await index.findSymbols(query: "TransientType")
        let semantic = await index.semanticIndex.search(query: "TransientType", targetDirectories: [], numResults: 10)
        XCTAssertTrue(symbols.isEmpty)
        XCTAssertTrue(semantic.isEmpty)
    }

    func testIncrementalUpdateUsesContentHashWhenMTimeIsUnchanged() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("HashProbe.swift")
        try """
        final class HashProbe {
            func oldVersion() {
                print("old")
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let originalModDate = (try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date()
        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        let oldBeforeUpdate = await index.findSymbols(query: "oldVersion")
        XCTAssertFalse(oldBeforeUpdate.isEmpty)

        try """
        final class HashProbe {
            func newVersion() {
                print("new")
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: originalModDate], ofItemAtPath: file.path)

        _ = await index.incrementalUpdate()

        let newSymbols = await index.findSymbols(query: "newVersion")
        let oldSymbols = await index.findSymbols(query: "oldVersion")
        XCTAssertFalse(newSymbols.isEmpty, "Hash change should trigger incremental reindex even with unchanged mtime")
        XCTAssertTrue(oldSymbols.isEmpty, "Old symbol should be removed after reindex")
    }

    func testIncrementalUpdateReindexesOnlyChangedFiles() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let changed = workspace.appendingPathComponent("Changed.swift")
        let unchanged = workspace.appendingPathComponent("Unchanged.swift")
        try "struct Changed { func oldName() {} }\n".write(to: changed, atomically: true, encoding: .utf8)
        try "struct Unchanged { func keepName() {} }\n".write(to: unchanged, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let lock = NSLock()
        var parsedPaths: [String] = []
        let originalObserver = SymbolExtractor.indexFileWithContentObserver
        SymbolExtractor.indexFileWithContentObserver = { path in
            lock.lock()
            parsedPaths.append((path as NSString).lastPathComponent)
            lock.unlock()
        }
        defer {
            SymbolExtractor.indexFileWithContentObserver = originalObserver
        }

        try "struct Changed { func newName() {} }\n".write(to: changed, atomically: true, encoding: .utf8)
        _ = await index.incrementalUpdate()

        XCTAssertTrue(parsedPaths.contains("Changed.swift"))
        XCTAssertFalse(parsedPaths.contains("Unchanged.swift"))
    }

    func testStatusAndResultTotalFilesCountOnlyFiles() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "struct A {}\n".write(to: workspace.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}\n".write(to: nested.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        let result = await index.indexWorkspace(paths: [workspace])
        let status = await index.status()

        XCTAssertEqual(result.totalFiles, 2)
        XCTAssertEqual(status.totalFiles, 2)
    }

    func testIndexWorkspaceMultiRootLoadsGitignorePerRoot() async throws {
        let rootParent = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: rootParent) }

        let rootA = rootParent.appendingPathComponent("RootA", isDirectory: true)
        let rootB = rootParent.appendingPathComponent("RootB", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try "IgnoredA.swift\n".write(
            to: rootA.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "IgnoredB.swift\n".write(
            to: rootB.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        try "struct VisibleA {}\n".write(to: rootA.appendingPathComponent("VisibleA.swift"), atomically: true, encoding: .utf8)
        try "struct HiddenA {}\n".write(to: rootA.appendingPathComponent("IgnoredA.swift"), atomically: true, encoding: .utf8)
        try "struct VisibleB {}\n".write(to: rootB.appendingPathComponent("VisibleB.swift"), atomically: true, encoding: .utf8)
        try "struct HiddenB {}\n".write(to: rootB.appendingPathComponent("IgnoredB.swift"), atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [rootA, rootB], respectGitignore: true)

        let visibleA = await index.findSymbols(query: "VisibleA")
        let visibleB = await index.findSymbols(query: "VisibleB")
        let hiddenA = await index.findSymbols(query: "HiddenA")
        let hiddenB = await index.findSymbols(query: "HiddenB")

        XCTAssertFalse(visibleA.isEmpty)
        XCTAssertFalse(visibleB.isEmpty)
        XCTAssertTrue(hiddenA.isEmpty)
        XCTAssertTrue(hiddenB.isEmpty)
    }

    func testCancelledIndexWorkspaceDoesNotLeaveStatusStuckOnIndexing() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        for i in 0..<300 {
            try "struct CancelProbe\(i) { let value = \(i) }\n".write(
                to: workspace.appendingPathComponent("CancelProbe\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        let index = CodebaseIndex()
        let task = Task { await index.indexWorkspace(paths: [workspace]) }
        task.cancel()
        _ = await task.value

        let status = await index.status()
        XCTAssertNotEqual(status.status, .indexing)
    }

    func testCacheDirectoryUsesSoloCodeCacheNamespace() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cache-probe-\(UUID().uuidString)", isDirectory: true)
        let cacheDir = CodebaseIndex.cacheDirectory(for: [root])

        XCTAssertTrue(cacheDir.path.contains("/Caches/Solo Code/index/"))
    }
}
