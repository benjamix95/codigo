import XCTest
@testable import CoderEngine

final class PathFinderTests: XCTestCase {
    func testFindReturnsExecutableFromProvidedPath() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let executableName = "codex"
        let executableURL = tempDir.appendingPathComponent(executableName)
        XCTAssertTrue(fileManager.createFile(atPath: executableURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8)))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolved = PathFinder.find(
            executable: executableName,
            pathEnv: tempDir.path,
            allowInteractiveShellLookup: false,
            includeDefaultCandidates: false
        )

        XCTAssertEqual(resolved, executableURL.path)
    }

    func testFindDoesNotUseHomeFallbacksWhenDisabled() throws {
        let fileManager = FileManager.default
        let executableName = "codex-pathfinder-test-\(UUID().uuidString)"
        let homeExecutableURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent(executableName)

        try fileManager.createDirectory(
            at: homeExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(fileManager.createFile(
            atPath: homeExecutableURL.path,
            contents: Data("#!/bin/sh\nexit 0\n".utf8)
        ))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: homeExecutableURL.path)
        defer { try? fileManager.removeItem(at: homeExecutableURL) }

        let resolved = PathFinder.find(
            executable: executableName,
            pathEnv: "",
            allowInteractiveShellLookup: false,
            includeDefaultCandidates: false
        )

        XCTAssertNil(resolved)
    }

    @MainActor
    func testFindSkipsInteractiveShellLookupOnMainThread() throws {
        let fileManager = FileManager.default
        let executableName = "codex-main-thread-\(UUID().uuidString)"
        let executableURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(executableName)

        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(fileManager.createFile(
            atPath: executableURL.path,
            contents: Data("#!/bin/sh\nexit 0\n".utf8)
        ))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        defer { try? fileManager.removeItem(at: executableURL.deletingLastPathComponent()) }

        XCTAssertTrue(Thread.isMainThread)

        let resolved = PathFinder.find(
            executable: executableName,
            pathEnv: "",
            allowInteractiveShellLookup: true,
            includeDefaultCandidates: false
        )

        XCTAssertNil(resolved)
    }
}
