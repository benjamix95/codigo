import Foundation

extension OpenAIAPIProvider {
    static func supportsStreamUsage(baseURL: String) -> Bool {
        let lower = baseURL.lowercased()
        return lower.contains("/chat/completions")
    }

    static func extractUsage(from json: [String: Any]) -> (Int, Int)? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int)
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int)
        guard let input, let output else { return nil }
        return (input, output)
    }

    /// Check if an error response body indicates tools/function-calling is not supported.
    static func isToolUnsupportedError(_ body: String) -> Bool {
        let lower = body.lowercased()
        let toolKeywords = [
            "tool", "function", "tools", "function_call", "tool_choice",
            "not support", "unsupported", "not available", "does not support",
            "invalid parameter", "unrecognized request argument",
            "additional properties are not allowed",
        ]
        return toolKeywords.contains(where: { lower.contains($0) })
    }

    /// Read the full error body from a failed HTTP response.
    static func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        var buffer = [UInt8]()
        // Read up to 8KB of error body
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > 8192 { break }
            }
        } catch {
            // Ignore read errors for error body
        }
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }

    static let retryableHTTPStatusCodes: Set<Int> = [408, 409, 425, 429, 500, 502, 503, 504, 529]

    static func makeSession(timeoutSeconds: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = max(timeoutSeconds * 2, timeoutSeconds + 30)
        return URLSession(configuration: config)
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
        if nsError.domain != NSURLErrorDomain {
            return false
        }
        return isRetryableTransportCode(URLError.Code(rawValue: nsError.code))
    }

    static func isRetryableTransportCode(_ code: URLError.Code) -> Bool {
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

    static func receiveWebSocketMessage(
        socket: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await socket.receive()
            }
            group.addTask {
                try await sleep(seconds: timeoutSeconds)
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.unknown)
            }
            group.cancelAll()
            return first
        }
    }

    /// Extract a human-readable error message from an API error JSON body.
    static func extractErrorMessage(from body: String, statusCode: Int) -> String {
        guard let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let snippet = body.prefix(300)
            return "HTTP \(statusCode): \(snippet.isEmpty ? "empty response" : String(snippet))"
        }

        // OpenAI / OpenRouter format: { "error": { "message": "..." } }
        if let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            let errorType = (error["type"] as? String) ?? (error["code"] as? String) ?? ""
            let prefix = errorType.isEmpty ? "" : "[\(errorType)] "
            return "HTTP \(statusCode): \(prefix)\(message)"
        }

        // Alternative format: { "message": "..." }
        if let message = json["message"] as? String {
            return "HTTP \(statusCode): \(message)"
        }

        // Fallback
        return "HTTP \(statusCode): \(String(body.prefix(300)))"
    }

    static func shouldTryResponsesWebSocket(baseURL: String, imageURLs: [URL]?) -> Bool {
        if let imageURLs, !imageURLs.isEmpty { return false }
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else {
            return false
        }
        let isOpenAIHost = host == "api.openai.com" || host.hasSuffix(".openai.com")
        guard isOpenAIHost else { return false }
        return components.path.lowercased().contains("/chat/completions")
    }

    static func responsesWebSocketURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        let originalScheme = (components.scheme ?? "").lowercased()
        if originalScheme == "http" || originalScheme == "https" {
            components.scheme = originalScheme == "http" ? "ws" : "wss"
        } else if originalScheme == "ws" || originalScheme == "wss" {
            // Keep existing ws/wss scheme.
        } else {
            components.scheme = "wss"
        }
        components.path = "/v1/responses"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func responseInput(from content: Any) -> [[String: Any]] {
        if let text = content as? String {
            return [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text]
                ],
            ]]
        }

        guard let parts = content as? [[String: Any]] else {
            return [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": String(describing: content)]
                ],
            ]]
        }

        var userContent: [[String: Any]] = []
        for part in parts {
            let type = (part["type"] as? String ?? "").lowercased()
            if type == "text", let text = part["text"] as? String, !text.isEmpty {
                userContent.append(["type": "input_text", "text": text])
                continue
            }
            if type == "image_url",
               let imageObject = part["image_url"] as? [String: Any],
               let url = imageObject["url"] as? String,
               !url.isEmpty {
                var imagePayload: [String: Any] = ["type": "input_image", "image_url": url]
                if let detail = imageObject["detail"] as? String, !detail.isEmpty {
                    imagePayload["detail"] = detail
                }
                userContent.append(imagePayload)
            }
        }
        if userContent.isEmpty {
            userContent.append(["type": "input_text", "text": ""])
        }
        return [[
            "role": "user",
            "content": userContent,
        ]]
    }

    static func extractUsageFromResponseEvent(_ json: [String: Any]) -> (Int, Int)? {
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int)
            let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int)
            if let input, let output {
                return (input, output)
            }
        }
        if let response = json["response"] as? [String: Any],
           let usage = response["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int)
            let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int)
            if let input, let output {
                return (input, output)
            }
        }
        return nil
    }

    static func extractRealtimeErrorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let code = error["code"] as? String, !code.isEmpty {
                return code
            }
        }
        if let message = event["message"] as? String, !message.isEmpty {
            return message
        }
        return "Unknown WebSocket error"
    }

    static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let intValue = value as? Int {
            return String(intValue)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func responseEventToolCallId(from event: [String: Any]) -> String? {
        if let itemId = stringValue(event["item_id"]) { return itemId }
        if let callId = stringValue(event["call_id"]) { return callId }
        if let id = stringValue(event["id"]) { return id }
        if let outputIndex = stringValue(event["output_index"]) {
            return "idx-\(outputIndex)"
        }
        return nil
    }

}
