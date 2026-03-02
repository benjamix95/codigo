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
    private let maxRetries: Int
    private let timeoutSeconds: TimeInterval
    private let initialRetryDelaySeconds: TimeInterval
    private let maxRetryDelaySeconds: TimeInterval

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
        extraHeaders: [String: String] = [:],
        maxRetries: Int = 3,
        timeoutSeconds: TimeInterval = 60,
        initialRetryDelaySeconds: TimeInterval = 0.5,
        maxRetryDelaySeconds: TimeInterval = 8
    ) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.extraHeaders = extraHeaders
        self.maxRetries = max(1, maxRetries)
        self.timeoutSeconds = max(10, timeoutSeconds)
        self.initialRetryDelaySeconds = max(0.1, initialRetryDelaySeconds)
        self.maxRetryDelaySeconds = max(self.initialRetryDelaySeconds, maxRetryDelaySeconds)
    }

    public func isAuthenticated() -> Bool {
        !apiKey.isEmpty
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
        let maxRetries = self.maxRetries
        let timeoutSeconds = self.timeoutSeconds
        let initialRetryDelaySeconds = self.initialRetryDelaySeconds
        let maxRetryDelaySeconds = self.maxRetryDelaySeconds
        let session = Self.makeSession(timeoutSeconds: timeoutSeconds)
        let systemPrompt = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        let useOptimizerMode = context.systemPromptOverride != nil

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

                        let socket = session.webSocketTask(with: request)
                        socket.resume()
                        defer {
                            socket.cancel(with: .normalClosure, reason: nil)
                        }

                        var responsePayload: [String: Any] = [
                            "model": model,
                            "instructions": systemPrompt,
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
                            let message = try await Self.receiveWebSocketMessage(
                                socket: socket,
                                timeoutSeconds: timeoutSeconds
                            )
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

                        var currentAttempt = 1
                        var bytes: URLSession.AsyncBytes?
                        while currentAttempt <= maxRetries {
                            do {
                                let (attemptBytes, response) = try await session.bytes(for: request)

                                guard let httpResponse = response as? HTTPURLResponse else {
                                    throw CoderEngineError.apiError("Non-HTTP response from server")
                                }

                                let statusCode = httpResponse.statusCode
                                if (200...299).contains(statusCode) {
                                    bytes = attemptBytes
                                    break
                                }

                                let errorBody = await Self.readErrorBody(from: attemptBytes)

                                // If tools were included and the error is about tool incompatibility,
                                // signal that we should retry without tools.
                                if includeTools && Self.isToolUnsupportedError(errorBody) {
                                    return errorBody  // Signal: retry without tools
                                }

                                // For auth errors, throw immediately (not retriable)
                                if statusCode == 401 || statusCode == 403 {
                                    let msg = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                                    throw CoderEngineError.apiError("Authentication failed — \(msg)")
                                }

                                // For other 4xx errors when tools are included, try without tools
                                if includeTools && (statusCode == 400 || statusCode == 422) {
                                    return errorBody  // Signal: retry without tools
                                }

                                // Retriable HTTP status (429/5xx/timeout family)
                                if currentAttempt < maxRetries, Self.retryableHTTPStatusCodes.contains(statusCode) {
                                    let retryAfter = Self.retryAfterSeconds(from: httpResponse)
                                    let backoffDelay = Self.exponentialBackoffSeconds(
                                        attempt: currentAttempt,
                                        initialDelay: initialRetryDelaySeconds,
                                        maxDelay: maxRetryDelaySeconds
                                    )
                                    let delay = max(retryAfter ?? 0, backoffDelay)
                                    continuation.yield(.raw(type: "provider_retry", payload: [
                                        "provider": id,
                                        "attempt": "\(currentAttempt)",
                                        "max_attempts": "\(maxRetries)",
                                        "delay_ms": "\(Int(delay * 1000))",
                                        "reason": "http_\(statusCode)"
                                    ]))
                                    try await Self.sleep(seconds: delay)
                                    currentAttempt += 1
                                    continue
                                }

                                let msg = Self.extractErrorMessage(from: errorBody, statusCode: statusCode)
                                throw CoderEngineError.apiError(msg)
                            } catch {
                                if currentAttempt < maxRetries, Self.isRetryableTransportError(error) {
                                    let delay = Self.exponentialBackoffSeconds(
                                        attempt: currentAttempt,
                                        initialDelay: initialRetryDelaySeconds,
                                        maxDelay: maxRetryDelaySeconds
                                    )
                                    continuation.yield(.raw(type: "provider_retry", payload: [
                                        "provider": id,
                                        "attempt": "\(currentAttempt)",
                                        "max_attempts": "\(maxRetries)",
                                        "delay_ms": "\(Int(delay * 1000))",
                                        "reason": "transport_error"
                                    ]))
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
                    // In optimizer mode (systemPromptOverride), never use tools.
                    let initialIncludeTools = !useOptimizerMode
                    if Self.shouldTryResponsesWebSocket(baseURL: baseURL, imageURLs: imageURLs) {
                        var webSocketStarted = false
                        var wsAttempt = 1
                        while wsAttempt <= maxRetries {
                            do {
                                let first = try await attemptResponsesWebSocket(includeTools: initialIncludeTools)
                                webSocketStarted = first.didStart
                                if first.retrySignal != nil, initialIncludeTools {
                                    let second = try await attemptResponsesWebSocket(includeTools: false)
                                    webSocketStarted = webSocketStarted || second.didStart
                                }
                                return
                            } catch {
                                // If websocket already started streaming, do not fallback/retry
                                // to avoid duplicate output; propagate the original error.
                                if webSocketStarted {
                                    throw error
                                }

                                if wsAttempt < maxRetries, Self.isRetryableTransportError(error) {
                                    let delay = Self.exponentialBackoffSeconds(
                                        attempt: wsAttempt,
                                        initialDelay: initialRetryDelaySeconds,
                                        maxDelay: maxRetryDelaySeconds
                                    )
                                    continuation.yield(.raw(type: "provider_retry", payload: [
                                        "provider": id,
                                        "attempt": "\(wsAttempt)",
                                        "max_attempts": "\(maxRetries)",
                                        "delay_ms": "\(Int(delay * 1000))",
                                        "reason": "websocket_transport_error"
                                    ]))
                                    try await Self.sleep(seconds: delay)
                                    wsAttempt += 1
                                    continue
                                }

                                // Non-retriable websocket failure before stream start:
                                // silently fallback to SSE below.
                                break
                            }
                        }
                    }

                    let retrySignal = try await attemptStream(includeTools: initialIncludeTools)
                    if retrySignal != nil, initialIncludeTools {
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
