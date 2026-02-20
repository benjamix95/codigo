import XCTest
@testable import CoderIDE

final class PlanOptionsParserTests: XCTestCase {
    func testParseItalianOptionsWithMarkdownHeader() {
        let input = """
        ## Opzione 1: Refactor parser
        - Pro: robustezza

        ## Opzione 2: Patch minima
        - Pro: veloce
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].id, 1)
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("Refactor"))
        XCTAssertEqual(options[1].id, 2)
    }

    func testParseEnglishOptionsCaseInsensitive() {
        let input = """
        ## OPTION 1: Use strategy pattern
        details...

        ## option 2 - Keep current architecture
        details...
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.map(\.id), [1, 2])
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("strategy"))
    }
}

