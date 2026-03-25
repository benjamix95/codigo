import Foundation

extension OpenAIAPIProvider {
    static var maxRetryDelayTotalSeconds: TimeInterval { ProviderRetrySupport.maxRetryDelayTotalSeconds }
    static var retryableHTTPStatusCodes: Set<Int> { ProviderRetrySupport.retryableHTTPStatusCodes }

    static func supportsStreamUsage(baseURL: String) -> Bool {
        baseURL.lowercased().contains("/chat/completions")
    }

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

    static func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        await ProviderRetrySupport.readErrorBody(from: bytes)
    }

    static func makeSession(timeoutSeconds: TimeInterval) -> URLSession {
        ProviderRetrySupport.makeSession(timeoutSeconds: timeoutSeconds)
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

    static func exponentialBackoffSeconds(
        attempt: Int,
        initialDelay: TimeInterval,
        maxDelay: TimeInterval
    ) -> TimeInterval {
        ProviderRetrySupport.exponentialBackoffSeconds(
            attempt: attempt,
            initialDelay: initialDelay,
            maxDelay: maxDelay
        )
    }

    static func sleep(seconds: TimeInterval) async throws {
        try await ProviderRetrySupport.sleep(seconds: seconds)
    }

    // MARK: - WebSocket Helpers (OpenAI-specific)

    static func sendWebSocketMessageWithTimeout(
        socket: URLSessionWebSocketTask,
        message: URLSessionWebSocketTask.Message,
        timeoutSeconds: TimeInterval
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await socket.send(message) }
            group.addTask {
                try await sleep(seconds: timeoutSeconds)
                throw URLError(.timedOut)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    static func receiveWebSocketMessage(
        socket: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
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
               !url.isEmpty
            {
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
}
