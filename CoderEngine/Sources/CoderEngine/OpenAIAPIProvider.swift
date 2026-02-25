import Foundation

/// OpenAI-compatible API provider (usable for OpenAI, OpenRouter, MiniMax, and others).
public final class OpenAIAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )

    private let apiKey: String
    private let model: String
    private let reasoningEffort: String?
    private let baseURL: String
    private let extraHeaders: [String: String]

    /// Models that support reasoning effort: o1, o3, o4-mini.
    public static func isReasoningModel(_ name: String) -> Bool {
        name.hasPrefix("o1") || name.hasPrefix("o3") || name.hasPrefix("o4")
    }

    public init(
        apiKey: String,
        model: String = "gpt-4o-mini",
        reasoningEffort: String? = nil,
        id: String = "openai-api",
        displayName: String = "OpenAI API",
        baseURL: String = "https://api.openai.com/v1/chat/completions",
        extraHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.extraHeaders = extraHeaders
    }

    public func isAuthenticated() -> Bool {
        !apiKey.isEmpty
    }

    private static func supportsStreamUsage(baseURL: String) -> Bool {
        let lower = baseURL.lowercased()
        return lower.contains("/chat/completions")
    }

    private static func extractUsage(from json: [String: Any]) -> (Int, Int)? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int)
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int)
        guard let input, let output else { return nil }
        return (input, output)
    }

    /// Check if an error response body indicates tools/function-calling is not supported.
    private static func isToolUnsupportedError(_ body: String) -> Bool {
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
    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
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

    /// Extract a human-readable error message from an API error JSON body.
    private static func extractErrorMessage(from body: String, statusCode: Int) -> String {
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

    private static func shouldTryResponsesWebSocket(baseURL: String, imageURLs: [URL]?) -> Bool {
        if let imageURLs, !imageURLs.isEmpty { return false }
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else {
            return false
        }
        let isOpenAIHost = host == "api.openai.com" || host.hasSuffix(".openai.com")
        guard isOpenAIHost else { return false }
        return components.path.lowercased().contains("/chat/completions")
    }

    private static func responsesWebSocketURL(from baseURL: String) -> URL? {
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

    private static func responseInput(from content: Any) -> [[String: Any]] {
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

    private static func extractUsageFromResponseEvent(_ json: [String: Any]) -> (Int, Int)? {
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

    private static func extractRealtimeErrorMessage(from event: [String: Any]) -> String {
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

    private static func stringValue(_ value: Any?) -> String? {
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

    private static func responseEventToolCallId(from event: [String: Any]) -> String? {
        if let itemId = stringValue(event["item_id"]) { return itemId }
        if let callId = stringValue(event["call_id"]) { return callId }
        if let id = stringValue(event["id"]) { return id }
        if let outputIndex = stringValue(event["output_index"]) {
            return "idx-\(outputIndex)"
        }
        return nil
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        let baseURL = self.baseURL
        let extraHeaders = self.extraHeaders
        let reasoningEffort = self.reasoningEffort

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Build the content (text or multimodal with images)
                    var content: Any
                    if let urls = imageURLs, !urls.isEmpty {
                        var items: [[String: Any]] = []
                        for imgURL in urls {
                            if let data = try? Data(contentsOf: imgURL) {
                                let ext = imgURL.pathExtension.lowercased()
                                let mime =
                                    ext == "png"
                                    ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                                let b64 = data.base64EncodedString()
                                items.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:\(mime);base64,\(b64)"],
                                ])
                            }
                        }
                        if !items.isEmpty {
                            items.insert(["type": "text", "text": fullPrompt], at: 0)
                            content = items
                        } else {
                            content = fullPrompt
                        }
                    } else {
                        content = fullPrompt
                    }

                    let resolvedContent: Any = content

                    /// Attempt streaming via OpenAI Responses WebSocket mode (`/v1/responses`).
                    /// Returns nil if stream completed successfully.
                    /// Returns an error string when tools should be retried as text-only.
                    func attemptResponsesWebSocket(includeTools: Bool) async throws -> (
                        retrySignal: String?,
                        didStart: Bool
                    ) {
                        guard let wsURL = Self.responsesWebSocketURL(from: baseURL) else {
                            throw CoderEngineError.apiError(
                                "Invalid WebSocket URL from baseURL: \(baseURL)"
                            )
                        }

                        var request = URLRequest(url: wsURL)
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
                        for (key, value) in extraHeaders {
                            request.setValue(value, forHTTPHeaderField: key)
                        }

                        let socket = URLSession.shared.webSocketTask(with: request)
                        socket.resume()
                        defer {
                            socket.cancel(with: .normalClosure, reason: nil)
                        }

                        var responsePayload: [String: Any] = [
                            "model": model,
                            "instructions": SystemPrompts.taskCompletionStrict,
                            "input": Self.responseInput(from: resolvedContent),
                            "stream": true,
                        ]
                        if includeTools {
                            responsePayload["tools"] = Self.responseToolDefinitions
                        }
                        if Self.isReasoningModel(model), let effort = reasoningEffort {
                            responsePayload["reasoning"] = ["effort": effort]
                        }

                        let createEvent: [String: Any] = [
                            "type": "response.create",
                            "response": responsePayload,
                        ]

                        let encodedCreate = try JSONSerialization.data(withJSONObject: createEvent)
                        guard let createText = String(data: encodedCreate, encoding: .utf8) else {
                            throw CoderEngineError.apiError("Failed to encode WebSocket request")
                        }
                        try await socket.send(.string(createText))

                        var didEmitUsage = false
                        var didStartStream = false
                        var toolArgsById: [String: String] = [:]
                        var toolNameById: [String: String] = [:]
                        var finalizedToolIds = Set<String>()
                        var accumulatedReasoning = ""

                        while true {
                            let message = try await socket.receive()
                            let payloadText: String
                            switch message {
                            case .string(let text):
                                payloadText = text
                            case .data(let data):
                                payloadText = String(data: data, encoding: .utf8) ?? ""
                            @unknown default:
                                payloadText = ""
                            }
                            guard !payloadText.isEmpty,
                                  let data = payloadText.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data)
                                    as? [String: Any] else {
                                continue
                            }

                            let type = (json["type"] as? String ?? "").lowercased()
                            if type == "error" {
                                let errorMessage = Self.extractRealtimeErrorMessage(from: json)
                                if includeTools && Self.isToolUnsupportedError(errorMessage) {
                                    return (errorMessage, didStartStream)
                                }
                                throw CoderEngineError.apiError(errorMessage)
                            }

                            if type == "response.created", !didStartStream {
                                didStartStream = true
                                continuation.yield(.started)
                                continue
                            }

                            switch type {
                            case "response.output_text.delta":
                                if !didStartStream {
                                    didStartStream = true
                                    continuation.yield(.started)
                                }
                                if let delta = json["delta"] as? String, !delta.isEmpty {
                                    continuation.yield(.textDelta(delta))
                                }
                            case "response.reasoning_text.delta",
                                 "response.reasoning_summary_text.delta",
                                 "response.reasoning.delta":
                                if let delta = json["delta"] as? String, !delta.isEmpty {
                                    accumulatedReasoning += delta
                                    continuation.yield(
                                        .raw(type: "reasoning", payload: [
                                            "output": String(accumulatedReasoning.prefix(6_000)),
                                            "title": "Reasoning",
                                            "group_id": "reasoning-stream",
                                        ]))
                                }
                            case "response.function_call_arguments.delta":
                                guard let tcId = Self.responseEventToolCallId(from: json) else { break }
                                if let name = Self.stringValue(json["name"] ?? json["function_name"]) {
                                    toolNameById[tcId] = name
                                }
                                let fragment = (json["delta"] as? String) ?? ""
                                if fragment.isEmpty { break }
                                toolArgsById[tcId, default: ""] += fragment
                                continuation.yield(
                                    .raw(type: "tool_call_suggested", payload: [
                                        "id": tcId,
                                        "name": toolNameById[tcId] ?? "",
                                        "args_fragment": fragment,
                                        "args": toolArgsById[tcId] ?? "",
                                        "is_partial": "true",
                                    ]))
                            case "response.function_call_arguments.done":
                                guard let tcId = Self.responseEventToolCallId(from: json) else { break }
                                if let name = Self.stringValue(json["name"] ?? json["function_name"]) {
                                    toolNameById[tcId] = name
                                }
                                let args = (json["arguments"] as? String) ?? toolArgsById[tcId] ?? ""
                                toolArgsById[tcId] = args
                                finalizedToolIds.insert(tcId)
                                continuation.yield(
                                    .raw(type: "tool_call_suggested", payload: [
                                        "id": tcId,
                                        "name": toolNameById[tcId] ?? "",
                                        "args": args,
                                        "is_partial": "false",
                                    ]))
                            case "response.output_item.added", "response.output_item.done":
                                guard let item = json["item"] as? [String: Any],
                                      (item["type"] as? String)?.lowercased() == "function_call"
                                else {
                                    break
                                }
                                let tcId =
                                    Self.stringValue(item["id"])
                                    ?? Self.stringValue(item["call_id"])
                                    ?? Self.responseEventToolCallId(from: json)
                                    ?? UUID().uuidString
                                if let name = Self.stringValue(item["name"]) {
                                    toolNameById[tcId] = name
                                }
                                if let args = item["arguments"] as? String, !args.isEmpty {
                                    toolArgsById[tcId] = args
                                }
                                if type == "response.output_item.done" {
                                    let args = toolArgsById[tcId] ?? ""
                                    finalizedToolIds.insert(tcId)
                                    continuation.yield(
                                        .raw(type: "tool_call_suggested", payload: [
                                            "id": tcId,
                                            "name": toolNameById[tcId] ?? "",
                                            "args": args,
                                            "is_partial": "false",
                                        ]))
                                }
                            case "response.completed":
                                if let (inp, out) = Self.extractUsageFromResponseEvent(json) {
                                    continuation.yield(
                                        .raw(type: "usage", payload: [
                                            "input_tokens": "\(inp)",
                                            "output_tokens": "\(out)",
                                            "model": model,
                                        ]))
                                    didEmitUsage = true
                                }
                                for (tcId, args) in toolArgsById where !finalizedToolIds.contains(tcId) {
                                    continuation.yield(
                                        .raw(type: "tool_call_suggested", payload: [
                                            "id": tcId,
                                            "name": toolNameById[tcId] ?? "",
                                            "args": args,
                                            "is_partial": "false",
                                        ]))
                                }
                                if !didEmitUsage {
                                    continuation.yield(
                                        .raw(type: "usage", payload: [
                                            "input_tokens": "-1",
                                            "output_tokens": "-1",
                                            "model": model,
                                        ]))
                                }
                                continuation.yield(.completed)
                                continuation.finish()
                                return (nil, didStartStream)
                            case "response.failed":
                                throw CoderEngineError.apiError(Self.extractRealtimeErrorMessage(from: json))
                            default:
                                continue
                            }
                        }
                    }

                    /// Attempt the streaming request. If `includeTools` is true,
                    /// native function-calling tools are sent in the body.
                    /// Returns nil if the stream was consumed successfully via
                    /// the continuation; returns an error message if we should retry without tools.
                    @Sendable
                    func attemptStream(includeTools: Bool) async throws -> String? {
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
                                ["role": "system", "content": SystemPrompts.taskCompletionStrict],
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

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw CoderEngineError.apiError("Non-HTTP response from server")
                        }

                        // Handle non-2xx responses with proper error body reading
                        guard (200...299).contains(httpResponse.statusCode) else {
                            let errorBody = await Self.readErrorBody(from: bytes)
                            let statusCode = httpResponse.statusCode

                            // If tools were included and the error is about tool incompatibility,
                            // signal that we should retry without tools.
                            if includeTools && Self.isToolUnsupportedError(errorBody) {
                                return errorBody  // Signal: retry without tools
                            }

                            // For auth errors, throw specific error
                            if statusCode == 401 || statusCode == 403 {
                                let msg = Self.extractErrorMessage(
                                    from: errorBody, statusCode: statusCode)
                                throw CoderEngineError.apiError("Authentication failed — \(msg)")
                            }

                            // For rate limiting
                            if statusCode == 429 {
                                let msg = Self.extractErrorMessage(
                                    from: errorBody, statusCode: statusCode)
                                throw CoderEngineError.apiError("Rate limit exceeded — \(msg)")
                            }

                            // For other 4xx errors when tools are included, also try without tools
                            // (some providers return 400 or 422 for unsupported parameters)
                            if includeTools && (statusCode == 400 || statusCode == 422) {
                                return errorBody  // Signal: retry without tools
                            }

                            let msg = Self.extractErrorMessage(
                                from: errorBody, statusCode: statusCode)
                            throw CoderEngineError.apiError(msg)
                        }

                        // Successfully got a streaming response — consume it
                        continuation.yield(.started)

                        var buffer = [UInt8]()
                        var didEmitUsage = false
                        var toolArgsById: [String: String] = [:]
                        var toolNameById: [String: String] = [:]
                        var accumulatedReasoning = ""

                        for try await byte in bytes {
                            buffer.append(byte)
                            if byte == 10 {  // newline
                                let line =
                                    String(bytes: buffer, encoding: .utf8)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                buffer.removeAll()
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonStr = String(line.dropFirst(6))
                                if jsonStr == "[DONE]" {
                                    if !didEmitUsage {
                                        continuation.yield(
                                            .raw(
                                                type: "usage",
                                                payload: [
                                                    "input_tokens": "-1",
                                                    "output_tokens": "-1",
                                                    "model": model,
                                                ]))
                                    }
                                    continuation.yield(.completed)
                                    continuation.finish()
                                    return nil  // Success — fully consumed
                                }
                                guard let lineData = jsonStr.data(using: .utf8),
                                    let json = try? JSONSerialization.jsonObject(with: lineData)
                                        as? [String: Any]
                                else {
                                    // Some providers send SSE comments or non-JSON lines; skip them
                                    continue
                                }

                                // Check for inline error events (OpenRouter sends these sometimes)
                                if let error = json["error"] as? [String: Any],
                                    let errorMessage = error["message"] as? String
                                {
                                    continuation.yield(.error("API error: \(errorMessage)"))
                                    continue
                                }

                                if let (inp, out) = Self.extractUsage(from: json) {
                                    continuation.yield(
                                        .raw(
                                            type: "usage",
                                            payload: [
                                                "input_tokens": "\(inp)",
                                                "output_tokens": "\(out)",
                                                "model": model,
                                            ]))
                                    didEmitUsage = true
                                }
                                guard let choices = json["choices"] as? [[String: Any]],
                                    let first = choices.first
                                else {
                                    continue
                                }
                                if let delta = first["delta"] as? [String: Any] {
                                    // Reasoning content (o1, o3, o4-mini, DeepSeek R1, etc.)
                                    if let reasoningChunk = delta["reasoning_content"] as? String,
                                        !reasoningChunk.isEmpty
                                    {
                                        accumulatedReasoning += reasoningChunk
                                        let text = String(accumulatedReasoning.prefix(6_000))
                                        continuation.yield(
                                            .raw(
                                                type: "reasoning",
                                                payload: [
                                                    "output": text,
                                                    "title": "Reasoning",
                                                    "group_id": "reasoning-stream",
                                                ]))
                                    }
                                    // Tool calls (function calling)
                                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                        for toolCall in toolCalls {
                                            let tcId =
                                                (toolCall["id"] as? String)
                                                ?? "idx-\((toolCall["index"] as? Int).map(String.init) ?? "0")"
                                            if let function = toolCall["function"] as? [String: Any]
                                            {
                                                if let name = function["name"] as? String,
                                                    !name.isEmpty
                                                {
                                                    toolNameById[tcId] = name
                                                }
                                                if let argsFragment = function["arguments"]
                                                    as? String,
                                                    !argsFragment.isEmpty
                                                {
                                                    toolArgsById[tcId, default: ""] += argsFragment
                                                    continuation.yield(
                                                        .raw(
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
                                    // Text content
                                    if let textContent = delta["content"] as? String,
                                        !textContent.isEmpty
                                    {
                                        continuation.yield(.textDelta(textContent))
                                    }
                                }
                                if let finishReason = first["finish_reason"] as? String,
                                    finishReason == "tool_calls"
                                {
                                    for (tcId, args) in toolArgsById {
                                        continuation.yield(
                                            .raw(
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

                        // Stream ended without [DONE] — still emit completion
                        if !didEmitUsage {
                            continuation.yield(
                                .raw(
                                    type: "usage",
                                    payload: [
                                        "input_tokens": "-1",
                                        "output_tokens": "-1",
                                        "model": model,
                                    ]))
                        }
                        continuation.yield(.completed)
                        continuation.finish()
                        return nil  // Success
                    }

                    // --- Main execution ---
                    // 1) Prefer OpenAI Responses WebSocket mode when available.
                    // 2) Fallback to standard SSE chat/completions stream.
                    if Self.shouldTryResponsesWebSocket(baseURL: baseURL, imageURLs: imageURLs) {
                        var webSocketStarted = false
                        do {
                            let first = try await attemptResponsesWebSocket(includeTools: true)
                            webSocketStarted = first.didStart
                            if first.retrySignal != nil {
                                let second = try await attemptResponsesWebSocket(includeTools: false)
                                webSocketStarted = webSocketStarted || second.didStart
                            }
                            return
                        } catch {
                            // If websocket already started streaming, do not fallback to avoid
                            // duplicate output; propagate the original error.
                            if webSocketStarted {
                                throw error
                            }
                            // Otherwise silently fallback to SSE below.
                        }
                    }

                    let retrySignal = try await attemptStream(includeTools: true)
                    if retrySignal != nil {
                        let _ = try await attemptStream(includeTools: false)
                    }
                    // If an attempt returned nil, the stream was fully consumed and finished.

                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool Definitions

    private static var toolDefinitions: [[String: Any]] {
        ToolSchemaCatalog.openAIFunctionTools
    }

    private static var responseToolDefinitions: [[String: Any]] {
        toolDefinitions.compactMap { entry in
            let type = (entry["type"] as? String ?? "").lowercased()
            if type == "function", let function = entry["function"] as? [String: Any] {
                var normalized = function
                normalized["type"] = "function"
                return normalized
            }
            return entry
        }
    }
}

/// CoderEngine errors.
public enum CoderEngineError: Error, Sendable {
    case notAuthenticated
    case apiError(String)
    case cliNotFound(String)
}

extension CoderEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Provider is not authenticated"
        case .apiError(let message):
            return message
        case .cliNotFound(let path):
            return "CLI not found: \(path)"
        }
    }
}
