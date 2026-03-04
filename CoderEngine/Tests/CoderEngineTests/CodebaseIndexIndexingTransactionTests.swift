import Foundation
import XCTest
@testable import CoderEngine

final class CodebaseIndexIndexingTransactionTests: XCTestCase {
    func testCancelledIndexWorkspaceRollsBackStatusAndProgress() async throws {
        let workspace = try makeWorkspace(fileCount: 320)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let index = CodebaseIndex()
        let task = Task { await index.indexWorkspace(paths: [workspace]) }
        try await waitUntilIndexing(index)
        task.cancel()
        _ = await task.value

        let status = await index.status()
        XCTAssertEqual(status.status, .idle)
        XCTAssertNil(status.progress)
    }

    func testCancelledIncrementalUpdateRollsBackStatusAndProgress() async throws {
        let workspace = try makeWorkspace(fileCount: 240)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        for i in 0..<120 {
            try """
            struct Mutated\(i) {
                let value = \(i * 2)
            }
            """.write(
                to: workspace.appendingPathComponent("File\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        let task = Task { await index.incrementalUpdate() }
        try await waitUntilIndexing(index)
        task.cancel()
        _ = await task.value

        let status = await index.status()
        XCTAssertEqual(status.status, .idle)
        XCTAssertNil(status.progress)
    }

    private func makeWorkspace(fileCount: Int) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexing-transaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        for i in 0..<fileCount {
            try """
            struct Probe\(i) {
                let value = \(i)
            }
            """.write(
                to: workspace.appendingPathComponent("File\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return workspace
    }

    private func waitUntilIndexing(_ index: CodebaseIndex) async throws {
        for _ in 0..<80 {
            let status = await index.status()
            if status.status == .indexing {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timeout waiting for indexing status")
    }
}
