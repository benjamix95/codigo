import Foundation

/// Provider OpenAI-compatible via API diretta (usabile per OpenAI, OpenRouter, MiniMax, ecc.)
public final class OpenAIAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let apiKey: String
    private let model: String
    private let reasoningEffort: String?
    private let baseURL: String
    private let extraHeaders: [String: String]

    /// Modelli che supportano reasoning effort: o1, o3, o4-mini
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

                    /// Attempt the streaming request. If `includeTools` is true,
                    /// native function-calling tools are sent in the body.
                    /// Returns nil if the stream was consumed successfully via
                    /// the continuation; returns an error message if we should retry without tools.
                    @Sendable
                    func attemptStream(includeTools: Bool) async throws -> String? {
                        guard let url = URL(string: baseURL) else {
                            throw CoderEngineError.apiError("URL non valida: \(baseURL)")
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
                            throw CoderEngineError.apiError("Risposta non HTTP dal server")
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
                                throw CoderEngineError.apiError("Autenticazione fallita — \(msg)")
                            }

                            // For rate limiting
                            if statusCode == 429 {
                                let msg = Self.extractErrorMessage(
                                    from: errorBody, statusCode: statusCode)
                                throw CoderEngineError.apiError("Rate limit superato — \(msg)")
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
                                                    "title": "Ragionamento",
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

                    // --- Main execution: try with tools first, retry without if needed ---
                    let retrySignal = try await attemptStream(includeTools: true)

                    if let errorBody = retrySignal {
                        // First attempt failed due to tool incompatibility.
                        // Retry without tools — the ToolEnabledLLMProvider's text-based
                        // marker protocol will still work as a fallback.
                        let _ = try await attemptStream(includeTools: false)

                        // If we got here, the retry succeeded. The stream already
                        // completed via the continuation inside attemptStream.
                        // Swallow the original errorBody — it was a transient tool error.
                        _ = errorBody
                    }
                    // If attemptStream returned nil, the stream was fully consumed
                    // and continuation.finish() was already called.

                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool Definitions

    private static var toolDefinitions: [[String: Any]] {
        [
            functionTool(
                name: "read", description: "Read file content from workspace",
                properties: [
                    "path": [
                        "type": "string", "description": "File path absolute or workspace-relative",
                    ]
                ], required: ["path"]),
            functionTool(
                name: "glob", description: "Find files by glob-like pattern",
                properties: [
                    "pattern": ["type": "string", "description": "Pattern to match, e.g. *.swift"]
                ], required: ["pattern"]),
            functionTool(
                name: "grep", description: "Search text in files",
                properties: [
                    "query": ["type": "string", "description": "Text/regex query"],
                    "pathScope": ["type": "string", "description": "Optional folder/file scope"],
                ], required: ["query"]),
            functionTool(
                name: "edit", description: "Overwrite file with new content",
                properties: [
                    "path": ["type": "string", "description": "Target file path"],
                    "content": ["type": "string", "description": "Full file content to write"],
                ], required: ["path", "content"]),
            functionTool(
                name: "write", description: "Alias of edit",
                properties: [
                    "path": ["type": "string", "description": "Target file path"],
                    "content": ["type": "string", "description": "Full file content to write"],
                ], required: ["path", "content"]),
            functionTool(
                name: "bash", description: "Run shell command in workspace",
                properties: [
                    "command": ["type": "string", "description": "Shell command"]
                ], required: ["command"]),
            functionTool(
                name: "mcp", description: "Invoke MCP tool",
                properties: [
                    "tool": ["type": "string", "description": "MCP tool name"],
                    "args": ["type": "string", "description": "JSON string args"],
                ], required: ["tool"]),
            functionTool(
                name: "web_search", description: "Search web",
                properties: [
                    "query": ["type": "string", "description": "Search query"]
                ], required: ["query"]),
        ]
    }

    private static func functionTool(
        name: String,
        description: String,
        properties: [String: [String: String]],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ],
            ],
        ]
    }
}

/// Errori CoderEngine
public enum CoderEngineError: Error, Sendable {
    case notAuthenticated
    case apiError(String)
    case cliNotFound(String)
}
