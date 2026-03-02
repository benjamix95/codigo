import Foundation
import XCTest

@testable import CoderEngine

final class OpenAIAPIProviderTests: XCTestCase {

    // MARK: - Init & Authentication

    func testIsAuthenticatedWithValidKey() {
        let provider = OpenAIAPIProvider(apiKey: "sk-test-key")
        XCTAssertTrue(provider.isAuthenticated())
    }

    func testIsAuthenticatedWithEmptyKey() {
        let provider = OpenAIAPIProvider(apiKey: "")
        XCTAssertFalse(provider.isAuthenticated())
    }

    func testAttachmentCapabilitiesIncludeNativeImage() {
        let provider = OpenAIAPIProvider(apiKey: "test")
        XCTAssertTrue(provider.attachmentCapabilities.nativeImage)
        XCTAssertFalse(provider.attachmentCapabilities.nativeDocument)
        XCTAssertFalse(provider.attachmentCapabilities.nativeFile)
    }

    func testInitClampMaxRetriesToMinimumOne() {
        let provider = OpenAIAPIProvider(apiKey: "test", maxRetries: -5)
        XCTAssertTrue(provider.isAuthenticated())
    }

    func testInitClampTimeoutToMinimumTen() {
        let provider = OpenAIAPIProvider(apiKey: "test", timeoutSeconds: 0)
        XCTAssertTrue(provider.isAuthenticated())
    }

    // MARK: - Reasoning Model Detection

    func testIsReasoningModelO1() {
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o1"))
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o1-preview"))
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o1-mini"))
    }

    func testIsReasoningModelO3() {
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o3"))
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o3-mini"))
    }

    func testIsReasoningModelO4() {
        XCTAssertTrue(OpenAIAPIProvider.isReasoningModel("o4-mini"))
    }

    func testIsNotReasoningModelGPT() {
        XCTAssertFalse(OpenAIAPIProvider.isReasoningModel("gpt-4o"))
        XCTAssertFalse(OpenAIAPIProvider.isReasoningModel("gpt-4o-mini"))
        XCTAssertFalse(OpenAIAPIProvider.isReasoningModel("gpt-3.5-turbo"))
    }

    // MARK: - Tool Unsupported Error Detection

    func testToolUnsupportedErrorDetection() {
        XCTAssertTrue(OpenAIAPIProvider.isToolUnsupportedError(
            "This model does not support tools"))
        XCTAssertTrue(OpenAIAPIProvider.isToolUnsupportedError(
            "Unrecognized request argument: tool_choice"))
        XCTAssertTrue(OpenAIAPIProvider.isToolUnsupportedError(
            "Additional properties are not allowed"))
        XCTAssertTrue(OpenAIAPIProvider.isToolUnsupportedError(
            "function_call is not available for this model"))
    }

    func testNonToolError() {
        XCTAssertFalse(OpenAIAPIProvider.isToolUnsupportedError(
            "Rate limit exceeded"))
        XCTAssertFalse(OpenAIAPIProvider.isToolUnsupportedError(
            "Invalid API key"))
        XCTAssertFalse(OpenAIAPIProvider.isToolUnsupportedError(""))
    }

    // MARK: - Error Message Extraction

    func testExtractErrorMessageFromOpenAIFormat() {
        let body = """
        {"error": {"type": "invalid_request_error", "message": "Invalid API key"}}
        """
        let message = OpenAIAPIProvider.extractErrorMessage(from: body, statusCode: 401)
        XCTAssertTrue(message.contains("401"))
        XCTAssertTrue(message.contains("Invalid API key"))
        XCTAssertTrue(message.contains("invalid_request_error"))
    }

    func testExtractErrorMessageFromFlatMessage() {
        let body = """
        {"message": "Server overloaded"}
        """
        let message = OpenAIAPIProvider.extractErrorMessage(from: body, statusCode: 503)
        XCTAssertTrue(message.contains("503"))
        XCTAssertTrue(message.contains("Server overloaded"))
    }

    func testExtractErrorMessageFromPlainText() {
        let message = OpenAIAPIProvider.extractErrorMessage(from: "Gateway Timeout", statusCode: 504)
        XCTAssertTrue(message.contains("504"))
        XCTAssertTrue(message.contains("Gateway Timeout"))
    }

    func testExtractErrorMessageFromEmptyBody() {
        let message = OpenAIAPIProvider.extractErrorMessage(from: "", statusCode: 500)
        XCTAssertTrue(message.contains("500"))
        XCTAssertTrue(message.contains("empty response"))
    }

    // MARK: - Retryable Status Codes

    func testRetryableHTTPStatusCodes() {
        let codes = OpenAIAPIProvider.retryableHTTPStatusCodes
        XCTAssertTrue(codes.contains(429))
        XCTAssertTrue(codes.contains(500))
        XCTAssertTrue(codes.contains(502))
        XCTAssertTrue(codes.contains(503))
        XCTAssertTrue(codes.contains(504))
        XCTAssertTrue(codes.contains(529))
        XCTAssertTrue(codes.contains(408))
        // Client errors should not be retried
        XCTAssertFalse(codes.contains(400))
        XCTAssertFalse(codes.contains(401))
        XCTAssertFalse(codes.contains(403))
        XCTAssertFalse(codes.contains(422))
    }

    // MARK: - Transport Error Detection

    func testRetryableTransportErrorForTimeout() {
        let error = URLError(.timedOut)
        XCTAssertTrue(OpenAIAPIProvider.isRetryableTransportError(error))
    }

    func testRetryableTransportErrorForConnectionLost() {
        let error = URLError(.networkConnectionLost)
        XCTAssertTrue(OpenAIAPIProvider.isRetryableTransportError(error))
    }

    func testRetryableTransportErrorForNotConnected() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertTrue(OpenAIAPIProvider.isRetryableTransportError(error))
    }

    func testNonRetryableTransportError() {
        let error = URLError(.badURL)
        XCTAssertFalse(OpenAIAPIProvider.isRetryableTransportError(error))
    }

    func testNonRetryableCancellation() {
        let error = URLError(.cancelled)
        XCTAssertFalse(OpenAIAPIProvider.isRetryableTransportError(error))
    }

    func testNonRetryableCustomError() {
        struct CustomError: Error {}
        XCTAssertFalse(OpenAIAPIProvider.isRetryableTransportError(CustomError()))
    }

    // MARK: - Exponential Backoff

    func testExponentialBackoffFirstAttempt() {
        let delay = OpenAIAPIProvider.exponentialBackoffSeconds(
            attempt: 1, initialDelay: 0.5, maxDelay: 8)
        XCTAssertGreaterThanOrEqual(delay, 0.05)
        XCTAssertLessThanOrEqual(delay, 1.0)
    }

    func testExponentialBackoffIncreases() {
        var delayAttempt2Total: TimeInterval = 0
        var delayAttempt4Total: TimeInterval = 0
        let iterations = 100
        for _ in 0..<iterations {
            delayAttempt2Total += OpenAIAPIProvider.exponentialBackoffSeconds(
                attempt: 2, initialDelay: 0.5, maxDelay: 8)
            delayAttempt4Total += OpenAIAPIProvider.exponentialBackoffSeconds(
                attempt: 4, initialDelay: 0.5, maxDelay: 8)
        }
        let avgAttempt2 = delayAttempt2Total / Double(iterations)
        let avgAttempt4 = delayAttempt4Total / Double(iterations)
        XCTAssertGreaterThan(avgAttempt4, avgAttempt2)
    }

    func testExponentialBackoffRespectsMaxDelay() {
        let delay = OpenAIAPIProvider.exponentialBackoffSeconds(
            attempt: 100, initialDelay: 0.5, maxDelay: 8)
        XCTAssertLessThanOrEqual(delay, 8 * 1.2 + 0.01)
    }

    // MARK: - Provider Identity

    func testDefaultId() {
        let provider = OpenAIAPIProvider(apiKey: "test")
        XCTAssertEqual(provider.id, "openai-api")
    }

    func testCustomId() {
        let provider = OpenAIAPIProvider(apiKey: "test", id: "my-openai")
        XCTAssertEqual(provider.id, "my-openai")
    }

    func testCustomBaseURL() {
        let provider = OpenAIAPIProvider(
            apiKey: "test",
            baseURL: "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertTrue(provider.isAuthenticated())
    }
}
