import XCTest
@testable import CoderEngine

final class CoderEngineErrorTests: XCTestCase {

    // MARK: - ProviderHTTPError

    func testHTTPErrorDescription() {
        let error = CoderEngineError.httpError(ProviderHTTPError(
            providerId: "anthropic",
            statusCode: 429,
            message: "Rate limited",
            errorType: "rate_limit_error"
        ))
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("anthropic"))
        XCTAssertTrue(desc.contains("429"))
        XCTAssertTrue(desc.contains("rate_limit_error"))
        XCTAssertTrue(desc.contains("Rate limited"))
    }

    func testHTTPErrorWithoutType() {
        let error = ProviderHTTPError(
            providerId: "openai",
            statusCode: 500,
            message: "Internal error"
        )
        XCTAssertNil(error.errorType)
        XCTAssertTrue(error.isServerError)
        XCTAssertFalse(error.isAuthError)
        XCTAssertFalse(error.isRateLimited)
    }

    func testHTTPErrorAuthDetection() {
        let e401 = ProviderHTTPError(providerId: "x", statusCode: 401, message: "Unauthorized")
        let e403 = ProviderHTTPError(providerId: "x", statusCode: 403, message: "Forbidden")
        let e200 = ProviderHTTPError(providerId: "x", statusCode: 200, message: "OK")

        XCTAssertTrue(e401.isAuthError)
        XCTAssertTrue(e403.isAuthError)
        XCTAssertFalse(e200.isAuthError)
    }

    func testHTTPErrorRateLimitDetection() {
        let e429 = ProviderHTTPError(providerId: "x", statusCode: 429, message: "Too many")
        let e500 = ProviderHTTPError(providerId: "x", statusCode: 500, message: "Server error")

        XCTAssertTrue(e429.isRateLimited)
        XCTAssertFalse(e500.isRateLimited)
    }

    func testHTTPErrorServerErrorDetection() {
        for code in [500, 502, 503, 504] {
            let error = ProviderHTTPError(providerId: "x", statusCode: code, message: "err")
            XCTAssertTrue(error.isServerError, "Expected \(code) to be server error")
        }
        XCTAssertFalse(ProviderHTTPError(providerId: "x", statusCode: 400, message: "err").isServerError)
    }

    func testHTTPErrorEquatable() {
        let a = ProviderHTTPError(providerId: "anthropic", statusCode: 429, message: "Rate limit")
        let b = ProviderHTTPError(providerId: "anthropic", statusCode: 429, message: "Rate limit")
        XCTAssertEqual(a, b)
    }

    // MARK: - TransportError

    func testTransportErrorDescription() {
        let urlError = URLError(.timedOut)
        let error = CoderEngineError.transportError(
            ProviderTransportError(providerId: "openai", underlyingError: urlError)
        )
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("openai"))
        XCTAssertTrue(desc.contains("transport"))
    }

    func testTransportErrorExtractsURLErrorCode() {
        let urlError = URLError(.cannotConnectToHost)
        let te = ProviderTransportError(providerId: "test", underlyingError: urlError)
        XCTAssertEqual(te.urlErrorCode, URLError.Code.cannotConnectToHost.rawValue)
    }

    func testTransportErrorNonURLError() {
        struct CustomError: Error {}
        let te = ProviderTransportError(providerId: "test", underlyingError: CustomError())
        XCTAssertNil(te.urlErrorCode)
    }

    // MARK: - CircuitBreakerOpen

    func testCircuitBreakerOpenDescription() {
        let error = CoderEngineError.circuitBreakerOpen(providerId: "anthropic-api")
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("anthropic-api"))
        XCTAssertTrue(desc.contains("circuit breaker"))
    }

    // MARK: - CLIExecutionError

    func testCLIExecutionErrorDescription() {
        let error = CoderEngineError.cliExecutionFailed(CLIExecutionError(
            cliPath: "/usr/local/bin/codex",
            exitCode: 1,
            stderr: "command not found",
            providerId: "codex"
        ))
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("codex"))
        XCTAssertTrue(desc.contains("1"))
    }

    // MARK: - Backward Compatibility

    func testLegacyApiErrorStillWorks() {
        let error = CoderEngineError.apiError("Something went wrong")
        XCTAssertEqual(error.localizedDescription, "Something went wrong")
    }

    func testNotAuthenticatedStillWorks() {
        let error = CoderEngineError.notAuthenticated
        XCTAssertTrue(error.localizedDescription.contains("not authenticated"))
    }

    func testCliNotFoundStillWorks() {
        let error = CoderEngineError.cliNotFound("/usr/bin/claude")
        XCTAssertTrue(error.localizedDescription.contains("/usr/bin/claude"))
    }
}
