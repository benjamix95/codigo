import XCTest
@testable import CoderIDE

final class ContextPathResolverTests: XCTestCase {
    func testResolvePrefersActiveRoot() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootA = temp.appendingPathComponent("backend")
        let rootB = temp.appendingPathComponent("web")
        defer { try? fm.removeItem(at: temp) }
        try fm.createDirectory(at: rootA, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootB, withIntermediateDirectories: true)

        let rel = "src/index.ts"
        let pathA = rootA.appendingPathComponent(rel)
        let pathB = rootB.appendingPathComponent(rel)
        try fm.createDirectory(at: pathA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: pathB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "a".write(to: pathA, atomically: true, encoding: .utf8)
        try "b".write(to: pathB, atomically: true, encoding: .utf8)

        let context = ProjectContext(
            kind: .workspace,
            name: "ws",
            folderPaths: [rootA.path, rootB.path],
            isPinned: true,
            lastActiveFolderPath: rootB.path
        )

        let result = ContextPathResolver.resolve(reference: rel, context: context)
        switch result {
        case .resolved(let p):
            XCTAssertEqual(p, pathB.path)
        case .ambiguous(let matches):
            XCTFail("Expected resolved active root, got ambiguous: \(matches)")
        case .notFound:
            XCTFail("Expected resolved path")
        }
    }

    func testResolveNotFound() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .path
        let context = ProjectContext(kind: .singleProject, name: "one", folderPaths: [missingPath], isPinned: false)
        let result = ContextPathResolver.resolve(reference: "main.swift", context: context)
        if case .notFound = result {
            return
        }
        XCTFail("Expected .notFound")
    }

    func testResolveReturnsAmbiguousWithoutActiveRoot() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootA = temp.appendingPathComponent("a")
        let rootB = temp.appendingPathComponent("b")
        let rootC = temp.appendingPathComponent("c")
        defer { try? fm.removeItem(at: temp) }

        try fm.createDirectory(at: rootA, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootB, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootC, withIntermediateDirectories: true)

        let rel = "shared/file.txt"
        let pathB = rootB.appendingPathComponent(rel)
        let pathC = rootC.appendingPathComponent(rel)
        try fm.createDirectory(at: pathB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: pathC.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "y".write(to: pathB, atomically: true, encoding: .utf8)
        try "z".write(to: pathC, atomically: true, encoding: .utf8)

        let context = ProjectContext(
            kind: .workspace,
            name: "ws",
            folderPaths: [rootA.path, rootB.path, rootC.path],
            isPinned: false,
            lastActiveFolderPath: rootA.path
        )
        let result = ContextPathResolver.resolve(reference: rel, context: context)
        guard case .ambiguous(let matches) = result else {
            XCTFail("Expected .ambiguous")
            return
        }
        XCTAssertEqual(Set(matches), Set([pathB.path, pathC.path]))
    }
}
