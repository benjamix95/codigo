import XCTest
@testable import CoderEngine

final class CLIErrorClassifierTests: XCTestCase {

    // MARK: - Quota Detection

    func testClassify_quotaExhaustion() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "You have exceeded your quota limit"
        )
        XCTAssertTrue(result.isQuotaExhaustion)
        XCTAssertFalse(result.isRateLimited)
        XCTAssertEqual(result.normalizedCode, "openai:quota_exhausted")
    }

    func testClassify_billingIssue() {
        let result = CLIErrorClassifier.classify(
            providerId: "anthropic",
            message: "billing account suspended"
        )
        XCTAssertTrue(result.isQuotaExhaustion)
        XCTAssertEqual(result.normalizedCode, "anthropic:quota_exhausted")
    }

    // MARK: - Rate Limit Detection

    func testClassify_rateLimited() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "Rate limit exceeded. Too many requests."
        )
        XCTAssertTrue(result.isRateLimited)
        XCTAssertEqual(result.normalizedCode, "openai:rate_limited")
    }

    func testClassify_429Status() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "Error 429: too many requests"
        )
        XCTAssertTrue(result.isRateLimited)
    }

    // MARK: - Retry-After Parsing (static regex)

    func testClassify_retryAfterParsed() {
        let result = CLIErrorClassifier.classify(
            providerId: "anthropic",
            message: "Rate limit exceeded. Retry-After: 30"
        )
        XCTAssertTrue(result.isRateLimited)
        XCTAssertEqual(result.retryAfterSeconds, 30)
    }

    func testClassify_retryAfterWithDash() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "retry-after: 60 seconds"
        )
        XCTAssertEqual(result.retryAfterSeconds, 60)
    }

    func testClassify_noRetryAfter() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "Rate limit exceeded"
        )
        XCTAssertNil(result.retryAfterSeconds)
    }

    // MARK: - Generic Error

    func testClassify_genericError() {
        let result = CLIErrorClassifier.classify(
            providerId: "openai",
            message: "Internal server error"
        )
        XCTAssertFalse(result.isQuotaExhaustion)
        XCTAssertFalse(result.isRateLimited)
        XCTAssertNil(result.retryAfterSeconds)
        XCTAssertEqual(result.normalizedCode, "openai:generic_error")
    }

    // MARK: - Performance (regex statica)

    func testClassify_performanceWithStaticRegex() {
        // Verifica che la regex statica non causi problemi
        // eseguendo molte classificazioni in rapida successione.
        measure {
            for _ in 0..<1000 {
                _ = CLIErrorClassifier.classify(
                    providerId: "openai",
                    message: "Rate limit exceeded. Retry-After: 42"
                )
            }
        }
    }
}
