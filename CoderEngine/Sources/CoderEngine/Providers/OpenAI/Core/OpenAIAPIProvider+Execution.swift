import Foundation

extension OpenAIAPIProvider {
    func runStreamingRequest(
        fullPrompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let systemPrompt = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        let useOptimizerMode = context.systemPromptOverride != nil
        let resolvedContent = buildResolvedContent(prompt: fullPrompt, imageURLs: imageURLs)
        let session = Self.makeSession(timeoutSeconds: timeoutSeconds)
        let initialIncludeTools = !useOptimizerMode

        try Task.checkCancellation()

        if Self.shouldTryResponsesWebSocket(baseURL: baseURL, imageURLs: imageURLs) {
            var websocketStarted = false
            var websocketAttempt = 1

            while websocketAttempt <= maxRetries {
                do {
                    let first = try await attemptResponsesWebSocket(
                        includeTools: initialIncludeTools,
                        resolvedContent: resolvedContent,
                        systemPrompt: systemPrompt,
                        session: session,
                        continuation: continuation
                    )

                    websocketStarted = first.didStart

                    if first.retrySignal != nil, initialIncludeTools {
                        let second = try await attemptResponsesWebSocket(
                            includeTools: false,
                            resolvedContent: resolvedContent,
                            systemPrompt: systemPrompt,
                            session: session,
                            continuation: continuation
                        )
                        websocketStarted = websocketStarted || second.didStart
                    }

                    return
                } catch {
                    if websocketStarted {
                        throw error
                    }

                    if websocketAttempt < maxRetries, Self.isRetryableTransportError(error) {
                        let delay = Self.exponentialBackoffSeconds(
                            attempt: websocketAttempt,
                            initialDelay: initialRetryDelaySeconds,
                            maxDelay: maxRetryDelaySeconds
                        )

                        yieldProviderRetry(
                            continuation: continuation,
                            provider: id,
                            attempt: websocketAttempt,
                            maxAttempts: maxRetries,
                            delaySeconds: delay,
                            reason: "websocket_transport_error"
                        )

                        try await Self.sleep(seconds: delay)
                        websocketAttempt += 1
                        continue
                    }

                    // Non-retriable websocket failure before stream start:
                    // fallback silently to SSE below.
                    break
                }
            }
        }

        let retrySignal = try await attemptStream(
            includeTools: initialIncludeTools,
            resolvedContent: resolvedContent,
            systemPrompt: systemPrompt,
            session: session,
            continuation: continuation
        )

        if retrySignal != nil, initialIncludeTools {
            let _ = try await attemptStream(
                includeTools: false,
                resolvedContent: resolvedContent,
                systemPrompt: systemPrompt,
                session: session,
                continuation: continuation
            )
        }
    }

    private func buildResolvedContent(
        prompt: String,
        imageURLs: [URL]?
    ) -> Any {
        guard let urls = imageURLs, !urls.isEmpty else {
            return prompt
        }

        var items: [[String: Any]] = []
        for imgURL in urls {
            if let data = try? Data(contentsOf: imgURL) {
                let ext = imgURL.pathExtension.lowercased()
                let mime =
                    ext == "png"
                    ? "image/png"
                    : (ext == "gif" ? "image/gif" : "image/jpeg")
                let b64 = data.base64EncodedString()
                items.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mime);base64,\(b64)"],
                ])
            }
        }

        if items.isEmpty { return prompt }

        items.insert(["type": "text", "text": prompt], at: 0)
        return items
    }

    func yieldProviderRetry(
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        provider: String,
        attempt: Int,
        maxAttempts: Int,
        delaySeconds: TimeInterval,
        reason: String
    ) {
        continuation.yield(.raw(type: "provider_retry", payload: [
            "provider": provider,
            "attempt": "\(attempt)",
            "max_attempts": "\(maxAttempts)",
            "delay_ms": "\(Int(delaySeconds * 1000))",
            "reason": reason,
        ]))
    }
}
