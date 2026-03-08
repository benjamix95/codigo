import XCTest
@testable import CoderIDE

@MainActor
final class EditorQuickOpenStoreTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-quick-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "print(\"hi\")".write(
            to: rootURL.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try "export PATH=/usr/bin".write(
            to: rootURL.appendingPathComponent("Sources/env.sh"),
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        try super.tearDownWithError()
    }

    func testPrepareIndexesFilesAndQueryFiltersResults() async {
        let store = EditorQuickOpenStore()

        store.prepare(folderPaths: [rootURL.path])
        try? await Task.sleep(nanoseconds: 300_000_000)
        store.applyQuery("env")

        XCTAssertTrue(store.results.contains { $0.path.hasSuffix("env.sh") })
        XCTAssertFalse(store.results.contains { $0.path.hasSuffix("main.swift") })
    }
}
