import XCTest
@testable import CoderIDE

final class DebugClarificationPromptParserTests: XCTestCase {
    func testParse_extractsLetteredOptionsAndPreamble() {
        let raw = """
        Quando succede il flash?

        Nota importante:
        (a) primo caso
        (b) secondo caso
        """
        let p = DebugClarificationPromptParser.parse(raw)
        XCTAssertEqual(p.options.count, 2)
        XCTAssertEqual(p.options[0].letter, "a")
        XCTAssertTrue(p.options[0].text.contains("primo"))
        XCTAssertTrue(p.preamble.contains("Quando succede"))
        XCTAssertTrue(p.preamble.contains("Nota importante"))
    }

    func testParse_parenthesizedLetterStyle() {
        let raw = """
        Domanda?
        (a) uno
        (b) due
        (c) tre
        """
        let p = DebugClarificationPromptParser.parse(raw)
        XCTAssertEqual(p.options.count, 3)
        XCTAssertEqual(Set(p.options.map(\.letter)), Set(["a", "b", "c"]))
    }

    func testParse_singleOptionFallsBackToPlainText() {
        let raw = """
        Solo una riga
        (a) unique
        """
        let p = DebugClarificationPromptParser.parse(raw)
        XCTAssertTrue(p.options.isEmpty)
        XCTAssertTrue(p.preamble.contains("Solo una riga"))
    }

    func testParse_firstLineOptionLeavesEmptyPreamble() {
        let raw = """
        (a) start
        (b) next
        """
        let p = DebugClarificationPromptParser.parse(raw)
        XCTAssertEqual(p.options.count, 2)
        XCTAssertTrue(p.preamble.isEmpty)
    }

    func testParse_inlineLetteredOptionsOnSingleLine() {
        let raw = """
        Dimmi il caso più vicino: A) solo su retry B) solo con Claude C) sempre
        """
        let p = DebugClarificationPromptParser.parse(raw)
        XCTAssertEqual(p.options.map(\.letter), ["a", "b", "c"])
        XCTAssertEqual(p.options.map(\.text), ["solo su retry", "solo con Claude", "sempre"])
        XCTAssertTrue(p.preamble.contains("Dimmi il caso più vicino"))
    }
}
