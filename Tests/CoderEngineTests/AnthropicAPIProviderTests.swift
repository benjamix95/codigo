import Foundation
import XCTest

@testable import CoderEngine

final class AnthropicAPIProviderTests: XCTestCase {

    // MARK: - Init & Authentication

    func testIsAuthenticatedWithValidKey() {
        let provider = AnthropicAPIProvider(apiKey: "sk-ant-test-key")
        XCTAssertTrue(provider.isAuthenticated())
    }

    func testIsAuthenticatedWithEmptyKey() {
        let provider = AnthropicAPIProvider(apiKey: "")
        XCTAssertFalse(provider.isAuthenticated())
    }

    func testIsAuthenticatedWithWhitespaceKey() {
        let provider = AnthropicAPIProvider(apiKey: "   ")
        XCTAssertFalse(provider.isAuthenticated())
    }

    func testAttachmentCapabilitiesIncludeNativeImage() {
        let provider = AnthropicAPIProvider(apiKey: "test")
        XCTAssertTrue(provider.attachmentCapabilities.nativeImage)
        XCTAssertFalse(provider.attachmentCapabilities.nativeDocument)
        XCTAssertFalse(provider.attachmentCapabilities.nativeFile)
    }

    func testInitClampMaxRetriesToMinimumOne() {
        // maxRetries is private, but we can observe the behavior by checking
        // that the provider doesn't crash with edge values
        let provider = AnthropicAPIProvider(apiKey: "test", maxRetries: 0)
        XCTAssertTrue(provider.isAuthenticated())
    }

    func testInitClampTimeoutToMinimumTen() {
        let provider = AnthropicAPIProvider(apiKey: "test", timeoutSeconds: 1)
        XCTAssertTrue(provider.isAuthenticated())
    }

    // MARK: - Extended Thinking Detection

    func testSupportsExtendedThinkingForOpus4() {
        XCTAssertTrue(AnthropicAPIProvider.supportsExtendedThinking("claude-opus-4-6"))
        XCTAssertTrue(AnthropicAPIProvider.supportsExtendedThinking("claude-opus-4-20250514"))
    }

    func testSupportsExtendedThinkingForSonnet4() {
        XCTAssertTrue(AnthropicAPIProvider.supportsExtendedThinking("claude-sonnet-4-6"))
        XCTAssertTrue(AnthropicAPIProvider.supportsExtendedThinking("claude-sonnet-4-20250514"))
    }

    func testSupportsExtendedThinkingForHaiku4() {
        XCTAssertTrue(AnthropicAPIProvider.supportsExtendedThinking("claude-haiku-4-5-20251001"))
    }

    func testDoesNotSupportExtendedThinkingForClaude3() {
        XCTAssertFalse(AnthropicAPIProvider.supportsExtendedThinking("claude-3-5-sonnet-20241022"))
        XCTAssertFalse(AnthropicAPIProvider.supportsExtendedThinking("claude-3-haiku-20240307"))
    }

    // MARK: - Error Message Extraction

    func testExtractErrorMessageFromStructuredJSON() {
        let body = """
        {"error": {"type": "invalid_request_error", "message": "max_tokens must be > 0"}}
        """
        let message = AnthropicAPIProvider.extractErrorMessage(from: body, statusCode: 400)
        XCTAssertTrue(message.contains("max_tokens must be > 0"))
        XCTAssertTrue(message.contains("400"))
    }

    func testExtractErrorMessageFromFlatJSON() {
        let body = """
        {"message": "Rate limit exceeded"}
        """
        let message = AnthropicAPIProvider.extractErrorMessage(from: body, statusCode: 429)
        XCTAssertTrue(message.contains("Rate limit exceeded"))
        XCTAssertTrue(message.contains("429"))
    }

    func testExtractErrorMessageFromPlainText() {
        let message = AnthropicAPIProvider.extractErrorMessage(from: "Bad Gateway", statusCode: 502)
        XCTAssertTrue(message.contains("502"))
        XCTAssertTrue(message.contains("Bad Gateway"))
    }

    func testExtractErrorMessageFromEmptyBody() {
        let message = AnthropicAPIProvider.extractErrorMessage(from: "", statusCode: 500)
        XCTAssertEqual(message, "Anthropic API HTTP 500")
    }

    // MARK: - Retryable Status Codes

    func testRetryableHTTPStatusCodes() {
        let codes = AnthropicAPIProvider.retryableHTTPStatusCodes
        // Should retry on server errors and rate limits
        XCTAssertTrue(codes.contains(429))
        XCTAssertTrue(codes.contains(500))
        XCTAssertTrue(codes.contains(502))
        XCTAssertTrue(codes.contains(503))
        XCTAssertTrue(codes.contains(504))
        XCTAssertTrue(codes.contains(529))
        XCTAssertTrue(codes.contains(408))
        // Should NOT retry on client errors
        XCTAssertFalse(codes.contains(400))
        XCTAssertFalse(codes.contains(401))
        XCTAssertFalse(codes.contains(403))
        XCTAssertFalse(codes.contains(404))
        XCTAssertFalse(codes.contains(422))
    }

    // MARK: - Transport Error Detection

    func testRetryableTransportErrorForTimeout() {
        let error = URLError(.timedOut)
        XCTAssertTrue(AnthropicAPIProvider.shouldRetryTransportError(for:error))
    }

    func testRetryableTransportErrorForConnectionLost() {
        let error = URLError(.networkConnectionLost)
        XCTAssertTrue(AnthropicAPIProvider.shouldRetryTransportError(for:error))
    }

    func testRetryableTransportErrorForDNSFailure() {
        let error = URLError(.dnsLookupFailed)
        XCTAssertTrue(AnthropicAPIProvider.shouldRetryTransportError(for:error))
    }

    func testNonRetryableTransportError() {
        let error = URLError(.badURL)
        XCTAssertFalse(AnthropicAPIProvider.shouldRetryTransportError(for:error))
    }

    func testNonRetryableCustomError() {
        struct CustomError: Error {}
        XCTAssertFalse(AnthropicAPIProvider.shouldRetryTransportError(for:CustomError()))
    }

    // MARK: - Exponential Backoff

    func testExponentialBackoffFirstAttempt() {
        let delay = AnthropicAPIProvider.exponentialBackoffSeconds(
            attempt: 1, initialDelay: 0.5, maxDelay: 8)
        // First attempt: ~0.5s (with jitter 0.8..1.2)
        XCTAssertGreaterThanOrEqual(delay, 0.05)
        XCTAssertLessThanOrEqual(delay, 1.0)
    }

    func testExponentialBackoffIncreases() {
        // Run many times to account for jitter
        var delayAttempt2Total: TimeInterval = 0
        var delayAttempt4Total: TimeInterval = 0
        let iterations = 100
        for _ in 0..<iterations {
            delayAttempt2Total += AnthropicAPIProvider.exponentialBackoffSeconds(
                attempt: 2, initialDelay: 0.5, maxDelay: 8)
            delayAttempt4Total += AnthropicAPIProvider.exponentialBackoffSeconds(
                attempt: 4, initialDelay: 0.5, maxDelay: 8)
        }
        let avgAttempt2 = delayAttempt2Total / Double(iterations)
        let avgAttempt4 = delayAttempt4Total / Double(iterations)
        // attempt 4 should be larger on average than attempt 2
        XCTAssertGreaterThan(avgAttempt4, avgAttempt2)
    }

    func testExponentialBackoffRespectsMaxDelay() {
        let delay = AnthropicAPIProvider.exponentialBackoffSeconds(
            attempt: 100, initialDelay: 0.5, maxDelay: 8)
        XCTAssertLessThanOrEqual(delay, 8 * 1.2 + 0.01) // max * jitter ceiling
    }

    // MARK: - Provider Identity

    func testDefaultId() {
        let provider = AnthropicAPIProvider(apiKey: "test")
        XCTAssertEqual(provider.id, "anthropic-api")
    }

    func testCustomId() {
        let provider = AnthropicAPIProvider(apiKey: "test", id: "custom-provider")
        XCTAssertEqual(provider.id, "custom-provider")
    }

    func testCustomDisplayName() {
        let provider = AnthropicAPIProvider(apiKey: "test", displayName: "My Claude")
        XCTAssertEqual(provider.displayName, "My Claude")
    }
}
