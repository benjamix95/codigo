import Foundation
@testable import CoderEngine
import XCTest

final class CodebaseIndexCacheKeyTests: XCTestCase {
    func testIndexCachePathsKeySortsAndJoins() {
        let beta = URL(fileURLWithPath: "/work/beta")
        let alpha = URL(fileURLWithPath: "/work/alpha")
        XCTAssertEqual(
            CodebaseIndex.indexCachePathsKey(for: [beta, alpha]),
            "/work/alpha|/work/beta"
        )
    }

    func testIndexCacheDirectoryHashHexStableForOrderOfURLs() {
        let a = URL(fileURLWithPath: "/x/a")
        let b = URL(fileURLWithPath: "/x/b")
        let h1 = CodebaseIndex.indexCacheDirectoryHashHex(for: [a, b])
        let h2 = CodebaseIndex.indexCacheDirectoryHashHex(for: [b, a])
        XCTAssertEqual(h1, h2)
        XCTAssertFalse(h1.isEmpty)
    }
}
