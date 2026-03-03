import XCTest
@testable import CoderEngine

final class FileWatcherTests: XCTestCase {
    func testIngestPathsForTestingTracksDroppedPathsByReason() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let index = CodebaseIndex()
        let watcher = FileWatcher(index: index, workspacePaths: [workspace])
        await watcher.ingestPathsForTesting([
            workspace.appendingPathComponent("Notes.txt").path,
            workspace.appendingPathComponent(".hidden.swift").path,
            workspace.appendingPathComponent("node_modules/lib.swift").path,
            workspace.appendingPathComponent("Sources/App.swift").path,
        ])

        let metrics = await watcher.metrics()
        XCTAssertEqual(metrics.acceptedPaths, 1)
        XCTAssertEqual(metrics.droppedByExtension, 1)
        XCTAssertEqual(metrics.droppedHiddenPaths, 1)
        XCTAssertEqual(metrics.droppedIgnoredDirectories, 1)
    }
}
