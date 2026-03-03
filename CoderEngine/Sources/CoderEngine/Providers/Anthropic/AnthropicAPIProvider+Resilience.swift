import Foundation

extension AnthropicAPIProvider {
    static let maxRetryDelayTotalSeconds: TimeInterval = 120

    static let retryableHTTPStatusCodes: Set<Int> = [408, 409, 425, 429, 500, 502, 503, 504, 529]

    static func makeSession(timeoutSeconds: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = max(timeoutSeconds * 2, timeoutSeconds + 30)
        return URLSession(configuration: config)
    }

    static func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        var buffer = [UInt8]()
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 8192 { break }
            }
        } catch {
            // Ignore body parsing errors for failed HTTP responses.
        }
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }

    static func extractErrorMessage(from body: String, statusCode: Int) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty {
                return "Anthropic API HTTP \(statusCode)"
            }
            return "Anthropic API HTTP \(statusCode): \(String(snippet.prefix(300)))"
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return "Anthropic API HTTP \(statusCode): \(message)"
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return "Anthropic API HTTP \(statusCode): \(message)"
        }
        return "Anthropic API HTTP \(statusCode)"
    }

    static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let date = formatter.date(from: raw) {
            let delay = date.timeIntervalSinceNow
            return delay > 0 ? delay : nil
        }
        return nil
    }

    static func normalizeRetryAfter(_ value: TimeInterval?) -> TimeInterval {
        guard let retryAfter = value else {
            return 0
        }
        if !retryAfter.isFinite || retryAfter <= 0 {
            return 0
        }
        return min(max(0, retryAfter), maxRetryDelayTotalSeconds)
    }

    static func shouldRetryTransportError(for error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError {
            return isRetryableTransportError(urlError)
        }
        return isRetryableTransportError(error)
    }

    static func retryDelay(
        attempt: Int,
        initialDelay: TimeInterval,
        maxDelay: TimeInterval,
        retryAfter: TimeInterval?
    ) -> TimeInterval {
        let backoff = Self.exponentialBackoffSeconds(
            attempt: attempt,
            initialDelay: initialDelay,
            maxDelay: maxDelay
        )
        let serverDelay = Self.normalizeRetryAfter(retryAfter)
        return min(maxRetryDelayTotalSeconds, max(backoff, serverDelay))
    }

    static func isRetryableTransportError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .resourceUnavailable,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && isRetryableTransportError(URLError.Code(rawValue: nsError.code))
    }

    static func isRetryableTransportError(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    static func exponentialBackoffSeconds(
        attempt: Int,
        initialDelay: TimeInterval,
        maxDelay: TimeInterval
    ) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let exponential = min(maxDelay, initialDelay * pow(2.0, Double(exponent)))
        let jitter = Double.random(in: 0.8...1.2)
        return max(0.05, min(maxDelay, exponential * jitter))
    }

    static func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        let safeSeconds = max(0, seconds)
        let nanos = UInt64(safeSeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
        try Task.checkCancellation()
    }

}
