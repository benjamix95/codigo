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

        var currentAttempt = 1
        var bytes: URLSession.AsyncBytes?
        while currentAttempt <= maxRetries {
            try Task.checkCancellation()

            do {
                let (attemptBytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CoderEngineError.apiError("Invalid Anthropic API response")
                }
                let statusCode = httpResponse.statusCode
                if (200...299).contains(statusCode) {
                    bytes = attemptBytes
                    break
                }

                let errorBody = await Self.readErrorBody(from: attemptBytes)
                let errorMessage = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                let retryAfter = Self.retryAfterSeconds(from: httpResponse)

                if currentAttempt < maxRetries, Self.retryableHTTPStatusCodes.contains(statusCode) {
                    let backoffDelay = Self.exponentialBackoffSeconds(
                        attempt: currentAttempt,
                        initialDelay: initialRetryDelaySeconds,
                        maxDelay: maxRetryDelaySeconds
                    )
                    let delay = max(retryAfter ?? 0, backoffDelay)

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
                if currentAttempt < maxRetries, Self.isRetryableTransportError(error) {
                    let delay = Self.exponentialBackoffSeconds(
                        attempt: currentAttempt,
                        initialDelay: initialRetryDelaySeconds,
                        maxDelay: maxRetryDelaySeconds
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

        var lastUsage: (Int, Int)?
        var toolIdByContentBlock: [Int: String] = [:]
        var toolNameByContentBlock: [Int: String] = [:]
        var toolArgsByContentBlock: [Int: String] = [:]
        var accumulatedThinking = ""
        var buffer = [UInt8]()

        for try await byte in bytes {
            buffer.append(byte)
            if byte != 10 { continue } // newline

            let line = String(bytes: buffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            buffer.removeAll()

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                continuation.yield(.completed)
                continuation.finish()
                return
            }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            switch type {
            case "content_block_start":
                guard let index = json["index"] as? Int,
                      let block = json["content_block"] as? [String: Any] else { continue }
                let blockType = block["type"] as? String ?? ""
                if blockType == "thinking" {
                    accumulatedThinking = ""
                    continue
                }
                guard blockType == "tool_use" else { continue }

                let toolId = (block["id"] as? String) ?? "anthropic-\(index)"
                let toolName = (block["name"] as? String) ?? ""
                toolIdByContentBlock[index] = toolId
                toolNameByContentBlock[index] = toolName

                if let input = block["input"],
                   JSONSerialization.isValidJSONObject(input),
                   let inputData = try? JSONSerialization.data(withJSONObject: input),
                   let inputJson = String(data: inputData, encoding: .utf8) {
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
                guard let index = json["index"] as? Int,
                      let delta = json["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String else { continue }

                if deltaType == "thinking_delta",
                   let thinkingChunk = delta["thinking"] as? String, !thinkingChunk.isEmpty {
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
                    guard let text = delta["text"] as? String, !text.isEmpty else { continue }
                    continuation.yield(.textDelta(text))
                    continue
                }

                if deltaType == "input_json_delta" {
                    let fragment = (delta["partial_json"] as? String) ?? ""
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
                if let usage = json["usage"] as? [String: Any],
                   let inp = usage["input_tokens"] as? Int,
                   let out = usage["output_tokens"] as? Int {
                    lastUsage = (inp, out)
                }
            case "content_block_stop":
                guard let index = json["index"] as? Int,
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
                let errorPayload = json["error"] as? [String: Any]
                let message = errorPayload?["message"] as? String ?? "Anthropic API error"
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
