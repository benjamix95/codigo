import Foundation

extension AnthropicAPIProvider {
    static var maxRetryDelayTotalSeconds: TimeInterval { ProviderRetrySupport.maxRetryDelayTotalSeconds }
    static var retryableHTTPStatusCodes: Set<Int> { ProviderRetrySupport.retryableHTTPStatusCodes }

    static func makeSession(timeoutSeconds: TimeInterval) -> URLSession {
        ProviderRetrySupport.makeSession(timeoutSeconds: timeoutSeconds)
    }

    static func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        await ProviderRetrySupport.readErrorBody(from: bytes)
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
        ProviderRetrySupport.retryAfterSeconds(from: response)
    }

    static func shouldRetryTransportError(for error: Error) -> Bool {
        ProviderRetrySupport.shouldRetryTransportError(for: error)
    }

    static func retryDelay(
        attempt: Int,
        initialDelay: TimeInterval,
        maxDelay: TimeInterval,
        retryAfter: TimeInterval?
    ) -> TimeInterval {
        ProviderRetrySupport.retryDelay(
            attempt: attempt,
            initialDelay: initialDelay,
            maxDelay: maxDelay,
            retryAfter: retryAfter
        )
    }

    static func sleep(seconds: TimeInterval) async throws {
        try await ProviderRetrySupport.sleep(seconds: seconds)
    }
}
