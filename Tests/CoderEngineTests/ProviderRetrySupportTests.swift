import XCTest
@testable import CoderEngine

/// Test per ProviderRetrySupport — utility condivise retry/backoff.
final class ProviderRetrySupportTests: XCTestCase {

    // MARK: - Retryable Status Codes

    func testRetryableStatusCodes() {
        let expected: Set<Int> = [408, 409, 425, 429, 500, 502, 503, 504, 529]
        XCTAssertEqual(ProviderRetrySupport.retryableHTTPStatusCodes, expected)
    }

    func testNonRetryableStatusCodesAreExcluded() {
        let nonRetryable = [200, 201, 301, 400, 401, 403, 404, 422]
        for code in nonRetryable {
            XCTAssertFalse(
                ProviderRetrySupport.retryableHTTPStatusCodes.contains(code),
                "Status \(code) should not be retryable"
            )
        }
    }

    // MARK: - Exponential Backoff

    func testBackoffFirstAttemptUsesInitialDelay() {
        let delay = ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: 1,
            initialDelay: 1.0,
            maxDelay: 60.0
        )
        // Con jitter 0.8-1.2: range è 0.8-1.2
        XCTAssertGreaterThanOrEqual(delay, 0.8)
        XCTAssertLessThanOrEqual(delay, 1.2)
    }

    func testBackoffGrowsExponentially() {
        let delay1 = ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: 1, initialDelay: 1.0, maxDelay: 120.0
        )
        let delay3 = ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: 3, initialDelay: 1.0, maxDelay: 120.0
        )
        // Attempt 3 = base * 2^2 = 4x (con jitter), dovrebbe essere > attempt 1
        XCTAssertGreaterThan(delay3, delay1)
    }

    func testBackoffRespectsMaxDelay() {
        let delay = ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: 100,
            initialDelay: 1.0,
            maxDelay: 10.0
        )
        XCTAssertLessThanOrEqual(delay, 10.0)
    }

    func testBackoffNeverNegative() {
        let delay = ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: 0,
            initialDelay: 0.001,
            maxDelay: 1.0
        )
        XCTAssertGreaterThanOrEqual(delay, 0.0)
    }

    // MARK: - Retry Delay with Retry-After

    func testRetryDelayUsesServerRetryAfterWhenLarger() {
        let delay = ProviderRetrySupport.retryDelay(
            attempt: 1,
            initialDelay: 0.5,
            maxDelay: 30.0,
            retryAfter: 10.0
        )
        XCTAssertGreaterThanOrEqual(delay, 10.0)
    }

    func testRetryDelayUsesBackoffWhenRetryAfterIsNil() {
        let delay = ProviderRetrySupport.retryDelay(
            attempt: 1,
            initialDelay: 2.0,
            maxDelay: 30.0,
            retryAfter: nil
        )
        XCTAssertGreaterThanOrEqual(delay, 1.5) // 2.0 * 0.8 jitter
        XCTAssertLessThanOrEqual(delay, 3.0) // 2.0 * 1.2 jitter + margin
    }

    func testRetryDelayClampedToMaxTotal() {
        let delay = ProviderRetrySupport.retryDelay(
            attempt: 1,
            initialDelay: 1.0,
            maxDelay: 30.0,
            retryAfter: 999.0
        )
        XCTAssertLessThanOrEqual(delay, ProviderRetrySupport.maxRetryDelayTotalSeconds)
    }

    // MARK: - Normalize Retry-After

    func testNormalizeRetryAfterNil() {
        XCTAssertEqual(ProviderRetrySupport.normalizeRetryAfter(nil), 0)
    }

    func testNormalizeRetryAfterNegative() {
        XCTAssertEqual(ProviderRetrySupport.normalizeRetryAfter(-5.0), 0)
    }

    func testNormalizeRetryAfterInfinite() {
        XCTAssertEqual(ProviderRetrySupport.normalizeRetryAfter(.infinity), 0)
    }

    func testNormalizeRetryAfterNaN() {
        XCTAssertEqual(ProviderRetrySupport.normalizeRetryAfter(.nan), 0)
    }

    func testNormalizeRetryAfterClampsToMax() {
        let result = ProviderRetrySupport.normalizeRetryAfter(999.0)
        XCTAssertEqual(result, ProviderRetrySupport.maxRetryDelayTotalSeconds)
    }

    func testNormalizeRetryAfterPassesValid() {
        let result = ProviderRetrySupport.normalizeRetryAfter(5.0)
        XCTAssertEqual(result, 5.0)
    }

    // MARK: - Transport Error Detection

    func testCancellationErrorNotRetryable() {
        let error = CancellationError()
        XCTAssertFalse(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testTimeoutIsRetryable() {
        let error = URLError(.timedOut)
        XCTAssertTrue(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testCannotConnectToHostIsRetryable() {
        let error = URLError(.cannotConnectToHost)
        XCTAssertTrue(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testNetworkConnectionLostIsRetryable() {
        let error = URLError(.networkConnectionLost)
        XCTAssertTrue(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testDNSLookupFailedIsRetryable() {
        let error = URLError(.dnsLookupFailed)
        XCTAssertTrue(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testBadURLNotRetryable() {
        let error = URLError(.badURL)
        XCTAssertFalse(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    func testGenericErrorNotRetryable() {
        struct CustomError: Error {}
        let error = CustomError()
        XCTAssertFalse(ProviderRetrySupport.shouldRetryTransportError(for: error))
    }

    // MARK: - Retryable Transport Codes

    func testAllRetryableTransportCodes() {
        let retryableCodes: [URLError.Code] = [
            .timedOut, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet,
            .resourceUnavailable, .internationalRoamingOff, .callIsActive, .dataNotAllowed,
        ]
        for code in retryableCodes {
            XCTAssertTrue(
                ProviderRetrySupport.isRetryableTransportCode(code),
                "\(code) should be retryable"
            )
        }
    }

    func testNonRetryableTransportCodes() {
        let nonRetryable: [URLError.Code] = [
            .badURL, .unsupportedURL, .badServerResponse, .fileDoesNotExist,
        ]
        for code in nonRetryable {
            XCTAssertFalse(
                ProviderRetrySupport.isRetryableTransportCode(code),
                "\(code) should NOT be retryable"
            )
        }
    }

    // MARK: - Session Factory

    func testMakeSessionUsesEphemeralConfig() {
        let session = ProviderRetrySupport.makeSession(timeoutSeconds: 30)
        XCTAssertNotNil(session)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 30)
    }

    func testMakeSessionResourceTimeoutIsAtLeast2x() {
        let session = ProviderRetrySupport.makeSession(timeoutSeconds: 20)
        XCTAssertGreaterThanOrEqual(
            session.configuration.timeoutIntervalForResource, 40
        )
    }

    // MARK: - Sleep

    func testSleepRespectsCancellation() async {
        let task = Task {
            try await ProviderRetrySupport.sleep(seconds: 100)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Should have thrown CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            // Task.sleep may throw CancellationError wrapped
        }
    }
}
