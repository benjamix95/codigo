import Foundation
import XCTest
@testable import CoderEngine

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

    func testBuildFromIndexedFilesMatchesFilesystemTree() throws {
        let mainFile = tmpDir.appendingPathComponent("main.swift")
        let modelFile = tmpDir.appendingPathComponent("model.swift")
        try "func hello() {}".write(to: mainFile, atomically: true, encoding: .utf8)
        try "struct User {}".write(to: modelFile, atomically: true, encoding: .utf8)

        let indexedMain = try XCTUnwrap(
            SymbolExtractor.indexFileWithContent(
                absolutePath: mainFile.path,
                relativePath: "main.swift",
                language: .swift
            )
        )
        let indexedModel = try XCTUnwrap(
            SymbolExtractor.indexFileWithContent(
                absolutePath: modelFile.path,
                relativePath: "model.swift",
                language: .swift
            )
        )

        let filesystemTree = try XCTUnwrap(MerkleTree.build(root: tmpDir))
        let indexedTree = try XCTUnwrap(
            MerkleTree.build(
                indexedFiles: [indexedMain.file, indexedModel.file],
                contentCache: [
                    indexedMain.file.absolutePath: indexedMain.content,
                    indexedModel.file.absolutePath: indexedModel.content,
                ],
                workspaceRoot: tmpDir
            )
        )

        XCTAssertEqual(indexedTree.hash, filesystemTree.hash)
        XCTAssertEqual(MerkleTree.simHash(of: indexedTree), MerkleTree.simHash(of: filesystemTree))
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
