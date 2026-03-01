import XCTest
@testable import CoderIDE

final class CodeReviewPanelValidationTests: XCTestCase {

    // MARK: - isValidGitRefFormat

    func testValidRefs() {
        XCTAssertTrue(isValidGitRefFormat("main"))
        XCTAssertTrue(isValidGitRefFormat("HEAD"))
        XCTAssertTrue(isValidGitRefFormat("abc123def"))
        XCTAssertTrue(isValidGitRefFormat("feature/my-branch"))
        XCTAssertTrue(isValidGitRefFormat("v1.0.0"))
    }

    func testEmptyAndWhitespace() {
        XCTAssertFalse(isValidGitRefFormat(""))
        XCTAssertFalse(isValidGitRefFormat("   "))
        XCTAssertFalse(isValidGitRefFormat("\t"))
        XCTAssertFalse(isValidGitRefFormat("\n"))
    }

    func testFlagInjection() {
        XCTAssertFalse(isValidGitRefFormat("-flag"))
        XCTAssertFalse(isValidGitRefFormat("--exec=evil"))
    }

    func testDoubleDot() {
        XCTAssertFalse(isValidGitRefFormat("main..HEAD"))
        XCTAssertFalse(isValidGitRefFormat("a..b"))
    }

    func testForbiddenChars() {
        XCTAssertFalse(isValidGitRefFormat("ref with space"))
        XCTAssertFalse(isValidGitRefFormat("ref^2"))
        XCTAssertFalse(isValidGitRefFormat("ref:path"))
        XCTAssertFalse(isValidGitRefFormat("ref?"))
        XCTAssertFalse(isValidGitRefFormat("ref*"))
        XCTAssertFalse(isValidGitRefFormat("ref[0]"))
        XCTAssertFalse(isValidGitRefFormat("ref\\path"))
        XCTAssertFalse(isValidGitRefFormat("ref@{0}"))
    }

    func testDotLockSuffix() {
        XCTAssertFalse(isValidGitRefFormat("branch.lock"))
    }

    func testTrailingDot() {
        XCTAssertFalse(isValidGitRefFormat("branch."))
    }

    func testTildeRejected() {
        // ~ is forbidden by git-check-ref-format in ref names
        XCTAssertFalse(isValidGitRefFormat("HEAD~3"))
    }
}
