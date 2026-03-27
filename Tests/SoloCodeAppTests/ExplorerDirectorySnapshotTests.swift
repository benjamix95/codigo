import XCTest
@testable import CoderIDE

final class ExplorerDirectorySnapshotTests: XCTestCase {
    func testLoadExplorerEntriesFiltersHiddenAndExcludedPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let generated = sources.appendingPathComponent("Generated", isDirectory: true)
        let docs = root.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "print(\"ok\")".write(
            to: root.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "SECRET=1".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try "ignore".write(
            to: root.appendingPathComponent(".hidden"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let entries = SidePanelView.loadExplorerEntries(
            root: root.path,
            dir: root.path,
            excludedPaths: ["Sources/Generated"]
        )

        XCTAssertEqual(entries.map(\.name), ["Docs", "Sources", ".env", "App.swift"])
        XCTAssertTrue(entries.prefix(2).allSatisfy(\.isDirectory))
        XCTAssertFalse(entries.contains(where: { $0.name == ".hidden" }))
        XCTAssertFalse(entries.contains(where: { $0.fullPath.hasSuffix("Generated") }))
    }
}
