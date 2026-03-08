import XCTest
@testable import CoderEngine

extension SemanticIndexTests {
    func testTokenizeRemovesCodeKeywordStopwords() {
        let tokens = SemanticIndex.tokenizeStatic("import async return await data")

        XCTAssertFalse(tokens.contains("import"))
        XCTAssertFalse(tokens.contains("async"))
        XCTAssertFalse(tokens.contains("return"))
        XCTAssertFalse(tokens.contains("await"))
        XCTAssertTrue(tokens.contains("data"))
    }
}
