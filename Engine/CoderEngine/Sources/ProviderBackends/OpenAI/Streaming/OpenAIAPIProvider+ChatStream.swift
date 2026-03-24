import Foundation

extension OpenAIAPIProvider {
    func attemptStream(
        includeTools: Bool,
        resolvedContent: Any,
        systemPrompt: String,
        session: URLSession,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> String? {
        guard let url = URL(string: baseURL) else {
            throw CoderEngineError.apiError("Invalid URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": resolvedContent]
            ],
            "stream": true,
        ]
        if includeTools {
            body["tools"] = Self.toolDefinitions
            body["tool_choice"] = "auto"
        }
        if Self.supportsStreamUsage(baseURL: baseURL) {
            body["stream_options"] = ["include_usage": true]
        }
        if Self.isReasoningModel(model), let effort = reasoningEffort {
            body["reasoning"] = ["effort": effort]
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
                    yieldProviderRetry(
                        continuation: continuation,
                        provider: id,
                        attempt: currentAttempt,
                        maxAttempts: maxRetries,
                        delaySeconds: retryAfter,
                        reason: "circuit_breaker_open"
                    )
                    try await Self.sleep(seconds: min(retryAfter, Self.maxRetryDelayTotalSeconds))
                    currentAttempt += 1
                    continue
                }
                throw CoderEngineError.apiError("Provider circuit breaker open — \(id) unavailable")
            }

            do {
                let (attemptBytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CoderEngineError.apiError("Non-HTTP response from server")
                }

                let statusCode = httpResponse.statusCode
                if (200...299).contains(statusCode) {
                    await circuitBreaker.recordSuccess()
                    bytes = attemptBytes
                    break
                }

                let errorBody = await Self.readErrorBody(from: attemptBytes)

                if includeTools && Self.isToolUnsupportedError(errorBody) {
                    return errorBody
                }

                if statusCode == 401 || statusCode == 403 {
                    let msg = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                    throw CoderEngineError.apiError("Authentication failed — \(msg)")
                }

                if includeTools && (statusCode == 400 || statusCode == 422) {
                    return errorBody
                }

                await circuitBreaker.recordFailure()

                if currentAttempt < maxRetries, Self.retryableHTTPStatusCodes.contains(statusCode) {
                    let retryAfter = Self.retryAfterSeconds(from: httpResponse)
                    let delay = Self.retryDelay(
                        attempt: currentAttempt,
                        initialDelay: initialRetryDelaySeconds,
                        maxDelay: maxRetryDelaySeconds,
                        retryAfter: retryAfter
                    )

                    yieldProviderRetry(
                        continuation: continuation,
                        provider: id,
                        attempt: currentAttempt,
                        maxAttempts: maxRetries,
                        delaySeconds: delay,
                        reason: "http_\(statusCode)"
                    )

                    try await Self.sleep(seconds: delay)
                    currentAttempt += 1
                    continue
                }

                let msg = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                throw CoderEngineError.apiError(msg)
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

                    yieldProviderRetry(
                        continuation: continuation,
                        provider: id,
                        attempt: currentAttempt,
                        maxAttempts: maxRetries,
                        delaySeconds: delay,
                        reason: "transport_error"
                    )

                    try await Self.sleep(seconds: delay)
                    currentAttempt += 1
                    continue
                }
                throw error
            }
        }

        guard let bytes else {
            throw CoderEngineError.apiError("Failed to connect after \(maxRetries) attempts")
        }

        continuation.yield(.started)

        let decoder = JSONDecoder()
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576 // 1 MB limite per frame SSE
        var skipUntilNewline = false
        var didEmitUsage = false
        var toolArgsById: [String: String] = [:]
        var toolNameById: [String: String] = [:]
        var accumulatedReasoning = ""

        for try await byte in bytes {
            // Dopo un overflow, scarta tutto fino al prossimo newline
            // per evitare di contaminare il frame successivo.
            if skipUntilNewline {
                if byte == 10 { skipUntilNewline = false }
                continue
            }

            buffer.append(byte)

            // Protezione: frame senza newline non devono crescere oltre il limite
            if buffer.count > maxSSEFrameBytes {
                let droppedSize = buffer.count
                buffer.removeAll()
                skipUntilNewline = true
                NSLog("[OpenAI SSE] Frame overflow: %d bytes exceeded %d limit — frame dropped", droppedSize, maxSSEFrameBytes)
                continuation.yield(.raw(type: "sse_frame_overflow", payload: [
                    "provider": id,
                    "dropped_bytes": "\(droppedSize)",
                    "limit_bytes": "\(maxSSEFrameBytes)",
                ]))
                continue
            }

            if byte == 10 {
                let line =
                    String(bytes: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                buffer.removeAll()
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" {
                    if !didEmitUsage {
                        continuation.yield(.raw(
                            type: "usage",
                            payload: [
                                "input_tokens": "-1",
                                "output_tokens": "-1",
                                "model": model,
                            ]))
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                    return nil
                }

                guard let lineData = jsonStr.data(using: .utf8),
                      let chunk = try? decoder.decode(OpenAIChatChunk.self, from: lineData)
                else {
                    continue
                }

                if let error = chunk.error, let errorMessage = error.message {
                    continuation.yield(.error("API error: \(errorMessage)"))
                    continue
                }

                if let usage = chunk.usage,
                   let inp = usage.resolvedInput,
                   let out = usage.resolvedOutput {
                    continuation.yield(.raw(
                        type: "usage",
                        payload: [
                            "input_tokens": "\(inp)",
                            "output_tokens": "\(out)",
                            "model": model,
                        ]))
                    didEmitUsage = true
                }

                guard let first = chunk.choices?.first else {
                    continue
                }

                if let delta = first.delta {
                    if let reasoningChunk = delta.reasoningContent,
                       !reasoningChunk.isEmpty
                    {
                        accumulatedReasoning += reasoningChunk
                        let text = String(accumulatedReasoning.prefix(6_000))
                        continuation.yield(.raw(
                            type: "reasoning",
                            payload: [
                                "output": text,
                                "title": "Reasoning",
                                "group_id": "reasoning-stream",
                            ]))
                    }

                    if let toolCalls = delta.toolCalls {
                        for toolCall in toolCalls {
                            let fallbackIndex = toolCall.index.map(String.init) ?? "0"
                            let tcId = toolCall.id ?? "idx-\(fallbackIndex)"
                            if let function = toolCall.function {
                                if let name = function.name, !name.isEmpty {
                                    toolNameById[tcId] = name
                                }
                                if let argsFragment = function.arguments,
                                   !argsFragment.isEmpty
                                {
                                    toolArgsById[tcId, default: ""] += argsFragment
                                    continuation.yield(.raw(
                                        type: "tool_call_suggested",
                                        payload: [
                                            "id": tcId,
                                            "name": toolNameById[tcId] ?? "",
                                            "args_fragment": argsFragment,
                                            "args": toolArgsById[tcId] ?? "",
                                            "is_partial": "true",
                                        ]))
                                }
                            }
                        }
                    }

                    if let textContent = delta.content, !textContent.isEmpty {
                        continuation.yield(.textDelta(textContent))
                    }
                }

                if first.finishReason == "tool_calls" {
                    for (tcId, args) in toolArgsById {
                        continuation.yield(.raw(
                            type: "tool_call_suggested",
                            payload: [
                                "id": tcId,
                                "name": toolNameById[tcId] ?? "",
                                "args": args,
                                "is_partial": "false",
                            ]))
                    }
                }
            }
        }

        if !didEmitUsage {
            continuation.yield(.raw(
                type: "usage",
                payload: [
                    "input_tokens": "-1",
                    "output_tokens": "-1",
                    "model": model,
                ]))
        }
        continuation.yield(.completed)
        continuation.finish()
        return nil
    }
}
