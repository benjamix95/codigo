import XCTest
@testable import CoderEngine

final class WordPieceTokenizerTests: XCTestCase {

    // MARK: - TokenizedInput Structure

    func testTokenizedInputHasCorrectLength() {
        // Without a real vocab file we test the structure directly.
        let input = TokenizedInput(
            inputIds: [Int32](repeating: 0, count: 512),
            attentionMask: [Int32](repeating: 0, count: 512),
            tokenCount: 10
        )
        XCTAssertEqual(input.inputIds.count, 512)
        XCTAssertEqual(input.attentionMask.count, 512)
        XCTAssertEqual(input.tokenCount, 10)
    }

    func testTokenizedInputSendable() {
        // TokenizedInput must be Sendable for actor boundaries.
        let input = TokenizedInput(
            inputIds: [101, 7592, 102],
            attentionMask: [1, 1, 1],
            tokenCount: 3
        )
        let task = Task { input.tokenCount }
        let _ = task
    }

    // MARK: - Special Token Constants

    func testSpecialTokenIds() {
        XCTAssertEqual(WordPieceTokenizer.clsTokenId, 101)
        XCTAssertEqual(WordPieceTokenizer.sepTokenId, 102)
        XCTAssertEqual(WordPieceTokenizer.padTokenId, 0)
        XCTAssertEqual(WordPieceTokenizer.unkTokenId, 100)
    }
}
