import XCTest
@testable import CoderIDE

@MainActor
final class OpenFilesStoreContextTests: XCTestCase {
    private var tempDirURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-files-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirURL {
            try? FileManager.default.removeItem(at: tempDirURL)
        }
        tempDirURL = nil
        try super.tearDownWithError()
    }

    func testOpenFilesForContextLoadsLinkedFileFromDisk() throws {
        let store = OpenFilesStore()
        let linkedFile = tempDirURL.appendingPathComponent("linked.swift")
        let content = "print(\"hello\")\n"
        try content.write(to: linkedFile, atomically: true, encoding: .utf8)

        let files = store.openFilesForContext(linkedPaths: [linkedFile.path])

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.path, linkedFile.path)
        XCTAssertEqual(files.first?.content, content)
    }
}
