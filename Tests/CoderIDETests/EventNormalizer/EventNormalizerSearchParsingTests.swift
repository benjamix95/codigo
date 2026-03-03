import XCTest
@testable import CoderIDE

final class EventNormalizerSearchParsingTests: XCTestCase {
    func testParseMatchLinesSkipsBinaryAndInvalidRowsAndTruncatesPreview() {
        let longPreview = String(repeating: "x", count: 700)
        let output = """
        Binary file Sources/Binary.dat matches
        Sources/Foo.swift:0:invalid line
        Sources/Foo.swift:12:\(longPreview)
        Sources/Bar.swift:3:valid
        """

        let matches = EventNormalizer.parseMatchLines(from: output)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].file, "Sources/Foo.swift")
        XCTAssertEqual(matches[0].line, 12)
        XCTAssertEqual(matches[0].preview.count, 500)
        XCTAssertEqual(matches[1].file, "Sources/Bar.swift")
        XCTAssertEqual(matches[1].line, 3)
    }

    func testParseSearchQueryFromCommandSupportsCaseInsensitiveCommandAndEqualsFlags() {
        let command = #"RG --glob=*.swift --type=swift "auth flow" Sources"#
        let query = EventNormalizer.parseSearchQueryFromCommand(command)
        XCTAssertEqual(query, "auth flow")
    }

    func testParseSearchQueryFromCommandExtractsRegexpFlagValues() {
        let equalsCommand = "grep --regexp=panic Sources"
        let attachedCommand = "rg -eAuthService Sources"

        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(equalsCommand), "panic")
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(attachedCommand), "AuthService")
    }

    func testParseInstantGrepAlignsMatchesCountWithParsedMatches() {
        let payload: [String: String] = [
            "query": "auth",
            "pathScope": "Sources",
            "matchesCount": "99",
            "previewLines": """
            Sources/A.swift:10:auth one
            Sources/B.swift:20:auth two
            """,
        ]

        let result = EventNormalizer.parseInstantGrep(payload: payload, timestamp: Date())

        XCTAssertEqual(result?.matches.count, 2)
        XCTAssertEqual(result?.matchesCount, 2)
    }
}
