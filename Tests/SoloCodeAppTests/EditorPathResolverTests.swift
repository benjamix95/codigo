import XCTest
@testable import CoderIDE

final class EditorPathResolverTests: XCTestCase {
    func testRelativePathResolvesAgainstMatchingRoot() {
        let path = "/tmp/workspace/Sources/App/main.swift"
        let roots = ["/tmp/workspace", "/tmp/other"]

        let resolved = EditorPathResolver.relativePath(for: path, roots: roots)

        XCTAssertEqual(resolved, "Sources/App/main.swift")
    }

    func testDisplayPathFallsBackToAbsolutePath() {
        let path = "/tmp/workspace/file.swift"
        let display = EditorPathResolver.displayPath(path, roots: ["/tmp/other"])
        XCTAssertEqual(display, path)
    }
}
