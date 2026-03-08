import XCTest
@testable import CoderEngine

extension WebToolsTests {
    // MARK: - WebToolsError

    func testWebToolsErrorDescriptions() {
        let errors: [WebToolsError] = [
            .invalidURL("https://bad.url"),
            .httpError(404),
            .decodingFailed,
            .searchFailed("timeout"),
            .timeout,
            .noResults,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testWebToolsErrorInvalidURLContainsURL() {
        let error = WebToolsError.invalidURL("https://bad.url")
        XCTAssertTrue(error.errorDescription!.contains("https://bad.url"))
    }

    func testWebToolsErrorHTTPContainsCode() {
        let error = WebToolsError.httpError(503)
        XCTAssertTrue(error.errorDescription!.contains("503"))
    }

    func testWebToolsErrorSearchFailedContainsMessage() {
        let error = WebToolsError.searchFailed("rate limited")
        XCTAssertTrue(error.errorDescription!.contains("rate limited"))
    }
}
