import Foundation

extension AnthropicAPIProvider {
    func runStreamingRequest(
        fullPrompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let session = Self.makeSession(timeoutSeconds: timeoutSeconds)
        let systemPrompt = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        let useOptimizerMode = context.systemPromptOverride != nil

        let resolvedContent = buildRequestContent(prompt: fullPrompt, imageURLs: imageURLs)

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw CoderEngineError.apiError("Invalid Anthropic API URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": resolvedContent
                ]
            ],
        ]
        if !useOptimizerMode {
            body["tools"] = AnthropicAPIProvider.toolDefinitions
        }
        if Self.supportsExtendedThinking(model) {
            body["thinking"] = ["type": "enabled", "budget_tokens": 10_000]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeoutSeconds

        let circuitBreaker = await ProviderCircuitBreakerRegistry.shared.breaker(for: id)

        var currentAttempt = 1
        var bytes: URLSession.AsyncBytes?
        while currentAttempt <= maxRetries {
            try Task.checkCancellation()

            let decision = await circuitBreaker.shouldAllow()
            if case .reject(let retryAfter) = decision {
                if currentAttempt < maxRetries {
                    continuation.yield(.raw(type: "provider_retry", payload: [
                        "provider": "anthropic",
                        "attempt": "\(currentAttempt)",
                        "max_attempts": "\(maxRetries)",
                        "delay_ms": "\(Int(retryAfter * 1000))",
                        "reason": "circuit_breaker_open",
                    ]))
                    try await Self.sleep(seconds: min(retryAfter, Self.maxRetryDelayTotalSeconds))
                    currentAttempt += 1
                    continue
                }
                throw CoderEngineError.apiError("Anthropic API circuit breaker open — provider unavailable")
            }

            do {
                let (attemptBytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CoderEngineError.apiError("Invalid Anthropic API response")
                }
                let statusCode = httpResponse.statusCode
                if (200...299).contains(statusCode) {
                    await circuitBreaker.recordSuccess()
                    bytes = attemptBytes
                    break
                }

                let errorBody = await Self.readErrorBody(from: attemptBytes)
                let errorMessage = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                let retryAfter = Self.retryAfterSeconds(from: httpResponse)

                await circuitBreaker.recordFailure()

                if currentAttempt < maxRetries, Self.retryableHTTPStatusCodes.contains(statusCode) {
                    let delay = Self.retryDelay(
                        attempt: currentAttempt,
                        initialDelay: initialRetryDelaySeconds,
                        maxDelay: maxRetryDelaySeconds,
                        retryAfter: retryAfter
                    )

                    continuation.yield(.raw(type: "provider_retry", payload: [
                        "provider": "anthropic",
                        "attempt": "\(currentAttempt)",
                        "max_attempts": "\(maxRetries)",
                        "delay_ms": "\(Int(delay * 1000))",
                        "reason": "http_\(statusCode)",
                    ]))

                    try await Self.sleep(seconds: delay)
                    currentAttempt += 1
                    continue
                }

                throw CoderEngineError.apiError(errorMessage)
            } catch {
                if error is CancellationError {
                    throw error
                }

                await circuitBreaker.recordFailure()

                if currentAttempt < maxRetries, Self.shouldRetryTransportError(for: error) {
                    let delay = Self.retryDelay(
                        attempt: currentAttempt,
                        initialDelay: initialRetryDelaySeconds,
                        maxDelay: maxRetryDelaySeconds,
                        retryAfter: nil
                    )

                    continuation.yield(.raw(type: "provider_retry", payload: [
                        "provider": "anthropic",
                        "attempt": "\(currentAttempt)",
                        "max_attempts": "\(maxRetries)",
                        "delay_ms": "\(Int(delay * 1000))",
                        "reason": "transport_error",
                    ]))

                    try await Self.sleep(seconds: delay)
                    currentAttempt += 1
                    continue
                }
                throw error
            }
        }

        guard let bytes else {
            throw CoderEngineError.apiError("Failed to connect to Anthropic API after \(maxRetries) attempts")
        }

        continuation.yield(.started)

        let decoder = JSONDecoder()
        var lastUsage: (Int, Int)?
        var toolIdByContentBlock: [Int: String] = [:]
        var toolNameByContentBlock: [Int: String] = [:]
        var toolArgsByContentBlock: [Int: String] = [:]
        var accumulatedThinking = ""
        var sseParser = SSELineParser()

        for try await byte in bytes {
            let lineResult = sseParser.feed(byte)

            switch lineResult {
            case .buffering:
                continue
            case .overflow(let droppedBytes):
                NSLog("[Anthropic SSE] Frame overflow: %d bytes dropped", droppedBytes)
                continuation.yield(.raw(type: "sse_frame_overflow", payload: [
                    "provider": "anthropic",
                    "dropped_bytes": "\(droppedBytes)",
                    "limit_bytes": "\(sseParser.maxFrameBytes)",
                ]))
                continue
            case .done:
                continuation.yield(.completed)
                continuation.finish()
                return
            case .payload:
                break
            }

            guard case .payload(let jsonStr) = lineResult,
                  let data = jsonStr.data(using: .utf8),
                  let event = try? decoder.decode(AnthropicSSEEvent.self, from: data)
            else { continue }

            switch event.type {
            case "content_block_start":
                guard let index = event.index,
                      let block = event.contentBlock else { continue }
                if block.type == "thinking" {
                    accumulatedThinking = ""
                    continue
                }
                guard block.type == "tool_use" else { continue }

                let toolId = block.id ?? "anthropic-\(index)"
                let toolName = block.name ?? ""
                toolIdByContentBlock[index] = toolId
                toolNameByContentBlock[index] = toolName

                if let inputJson = block.input?.toJSONString(), !inputJson.isEmpty {
                    toolArgsByContentBlock[index] = inputJson
                    continuation.yield(.raw(type: "tool_call_suggested", payload: [
                        "id": toolId,
                        "name": toolName,
                        "args": inputJson,
                        "is_partial": "false",
                    ]))
                } else {
                    continuation.yield(.raw(type: "tool_call_suggested", payload: [
                        "id": toolId,
                        "name": toolName,
                        "args": "",
                        "is_partial": "true",
                    ]))
                }
            case "content_block_delta":
                guard let index = event.index,
                      let delta = event.delta,
                      let deltaType = delta.type else { continue }

                if deltaType == "thinking_delta",
                   let thinkingChunk = delta.thinking, !thinkingChunk.isEmpty {
                    accumulatedThinking += thinkingChunk
                    let text = String(accumulatedThinking.prefix(6_000))
                    continuation.yield(.raw(type: "reasoning", payload: [
                        "output": text,
                        "title": "Reasoning",
                        "group_id": "reasoning-stream",
                    ]))
                    continue
                }

                if deltaType == "text_delta" {
                    guard let text = delta.text, !text.isEmpty else { continue }
                    continuation.yield(.textDelta(text))
                    continue
                }

                if deltaType == "input_json_delta" {
                    let fragment = delta.partialJson ?? ""
                    guard !fragment.isEmpty else { continue }
                    toolArgsByContentBlock[index, default: ""] += fragment
                    continuation.yield(.raw(type: "tool_call_suggested", payload: [
                        "id": toolIdByContentBlock[index] ?? "anthropic-\(index)",
                        "name": toolNameByContentBlock[index] ?? "",
                        "args_fragment": fragment,
                        "args": toolArgsByContentBlock[index] ?? "",
                        "is_partial": "true",
                    ]))
                    continue
                }
            case "message_delta":
                if let usage = event.usage,
                   let inp = usage.inputTokens,
                   let out = usage.outputTokens {
                    lastUsage = (inp, out)
                }
            case "content_block_stop":
                guard let index = event.index,
                      let toolId = toolIdByContentBlock[index],
                      let toolName = toolNameByContentBlock[index] else { continue }
                continuation.yield(.raw(type: "tool_call_suggested", payload: [
                    "id": toolId,
                    "name": toolName,
                    "args": toolArgsByContentBlock[index] ?? "",
                    "is_partial": "false",
                ]))
            case "message_stop":
                if let (inp, out) = lastUsage {
                    continuation.yield(.raw(type: "usage", payload: [
                        "input_tokens": "\(inp)",
                        "output_tokens": "\(out)",
                        "model": model,
                    ]))
                }
            case "error":
                let message = event.error?.message ?? "Anthropic API error"
                continuation.yield(.error(message))
            default:
                continue
            }
        }

        continuation.yield(.completed)
        continuation.finish()
    }

    private func buildRequestContent(prompt: String, imageURLs: [URL]?) -> [[String: Any]] {
        var content: [[String: Any]] = []
        if let urls = imageURLs, !urls.isEmpty {
            for imgURL in urls {
                if let data = try? Data(contentsOf: imgURL) {
                    let ext = imgURL.pathExtension.lowercased()
                    let mediaType: String
                    switch ext {
                    case "png":
                        mediaType = "image/png"
                    case "gif":
                        mediaType = "image/gif"
                    case "webp":
                        mediaType = "image/webp"
                    default:
                        mediaType = "image/jpeg"
                    }
                    let b64 = data.base64EncodedString()
                    content.append([
                        "type": "image",
                        "source": ["type": "base64", "media_type": mediaType, "data": b64]
                    ])
                }
            }
        }
        content.append(["type": "text", "text": prompt])
        return content
    }
}
