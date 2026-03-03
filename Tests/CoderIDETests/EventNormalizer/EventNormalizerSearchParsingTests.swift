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

    func testParseInstantGrepUsesReportedCountWhenPreviewIsMissing() {
        let payload: [String: String] = [
            "query": "auth",
            "pathScope": "Sources",
            "matchesCount": "17",
            "previewLines": "",
        ]

        let result = EventNormalizer.parseInstantGrep(payload: payload, timestamp: Date())
        XCTAssertEqual(result?.matches.count, 0)
        XCTAssertEqual(result?.matchesCount, 17)
    }

    func testParseInstantGrepFromCommandSupportsEnvPrefixedRg() {
        let payload: [String: String] = [
            "command": "NO_COLOR=1 RG -n --glob='*.swift' \"policy\" Sources",
            "cwd": "/tmp/workspace",
            "output": "Sources/App.swift:14:policy check"
        ]

        let result = EventNormalizer.parseInstantGrepFromCommand(payload: payload, timestamp: Date())
        XCTAssertEqual(result?.query, "policy")
        XCTAssertEqual(result?.matchesCount, 1)
        XCTAssertEqual(result?.matches.first?.file, "Sources/App.swift")
    }

    func testParseSearchQueryFromCommandSupportsAbsoluteBinaryPath() {
        let command = #"/usr/bin/rg -n "policy" Sources"#
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(command), "policy")
    }

    func testParseSearchQueryFromCommandSupportsShellWrapper() {
        let command = #"bash -lc 'rg -n "policy" Sources'"#
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(command), "policy")
    }

    func testParseSearchQueryFromCommandSkipsIncludeAndIgnoreFileValues() {
        let grep = #"grep -R --include "*.swift" policy Sources"#
        let rg = #"rg --ignore-file .gitignore policy Sources"#
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(grep), "policy")
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(rg), "policy")
    }

    func testParseSearchQueryFromCommandPreservesRegexEscapes() {
        let command = #"rg "\bAuth\b" Sources"#
        XCTAssertEqual(EventNormalizer.parseSearchQueryFromCommand(command), #"\bAuth\b"#)
    }

    func testParseMatchLinesSupportsWindowsDrivePrefix() {
        let output = #"C:\repo\App.swift:42:let auth = true"#
        let matches = EventNormalizer.parseMatchLines(from: output)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.file, #"C:\repo\App.swift"#)
        XCTAssertEqual(matches.first?.line, 42)
    }

    func testParseMatchLinesSupportsHeadingAndLineOnlyFormats() {
        let output = """
        Sources/Auth.swift
        12:let auth = true
        18:return auth
        """
        let matches = EventNormalizer.parseMatchLines(from: output)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].file, "Sources/Auth.swift")
        XCTAssertEqual(matches[0].line, 12)
        XCTAssertEqual(matches[1].line, 18)
    }

    func testParseMatchLinesSupportsNullSeparatedOutput() {
        let output = "Sources/Auth.swift\0 12:let auth = true"
        let matches = EventNormalizer.parseMatchLines(from: output)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.file, "Sources/Auth.swift")
        XCTAssertEqual(matches.first?.line, 12)
    }

    func testParseInstantGrepFromCommandReadsStderrFallback() {
        let payload: [String: String] = [
            "command": #"rg "policy" Sources"#,
            "cwd": "/tmp/workspace",
            "output": "",
            "stderr": "Sources/App.swift:9:policy fallback",
        ]
        let result = EventNormalizer.parseInstantGrepFromCommand(payload: payload, timestamp: Date())
        XCTAssertEqual(result?.matchesCount, 1)
        XCTAssertEqual(result?.matches.first?.line, 9)
    }

    func testExtractReadPathSupportsQuotedPathsWithSpaces() {
        let command = #"cat "Sources/My File.swift""#
        XCTAssertEqual(EventNormalizer.extractReadPath(from: command), "Sources/My File.swift")
    }
}
