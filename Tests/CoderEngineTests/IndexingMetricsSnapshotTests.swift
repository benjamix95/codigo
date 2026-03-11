import XCTest
@testable import CoderEngine

final class IndexingMetricsSnapshotTests: XCTestCase {
    func testMetricsSnapshotReflectsIndexedWorkspace() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-metrics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        try """
        struct SnapshotProbe {
            func tokenRefreshFlow() {}
        }
        """.write(
            to: workspace.appendingPathComponent("SnapshotProbe.swift"),
            atomically: true,
            encoding: .utf8
        )

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        let metrics = await index.metricsSnapshot()

        XCTAssertGreaterThanOrEqual(metrics.indexedFiles, 1)
        XCTAssertGreaterThanOrEqual(metrics.indexedSymbols, 1)
        XCTAssertGreaterThanOrEqual(metrics.indexDurationMs, 0)
        XCTAssertNotNil(metrics.lastFullIndexAt)
    }
}
