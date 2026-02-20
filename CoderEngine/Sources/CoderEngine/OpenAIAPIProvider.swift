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

    private static func decodeAPIError(data: Data, statusCode: Int) -> String {
        guard !data.isEmpty else { return "HTTP \(statusCode)" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    let code = (error["code"] as? String).map { " (\($0))" } ?? ""
                    return "HTTP \(statusCode)\(code): \(message)"
                }
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return "HTTP \(statusCode): \(message)"
            }
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return "HTTP \(statusCode): \(detail)"
            }
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        {
            return "HTTP \(statusCode): \(String(text.prefix(400)))"
        }
        return "HTTP \(statusCode)"
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        let baseURL = self.baseURL
        let extraHeaders = self.extraHeaders

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: baseURL)!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (key, value) in extraHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

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

                    var body: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "user", "content": content]
                        ],
                        "stream": true,
                    ]
                    body["tools"] = Self.toolDefinitions
                    body["tool_choice"] = "auto"
                    if Self.supportsStreamUsage(baseURL: baseURL) {
                        body["stream_options"] = ["include_usage": true]
                    }
                    if Self.isReasoningModel(model), let effort = reasoningEffort {
                        body["reasoning"] = ["effort": effort]
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(
                            throwing: CoderEngineError.apiError("Risposta HTTP non valida"))
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        var errorBytes = Data()
                        do {
                            for try await byte in bytes.prefix(32_768) {
                                errorBytes.append(byte)
                            }
                        } catch {
                            // Se il body non è leggibile manteniamo almeno status code.
                        }
                        let message = Self.decodeAPIError(
                            data: errorBytes,
                            statusCode: httpResponse.statusCode
                        )
                        continuation.finish(throwing: CoderEngineError.apiError(message))
                        return
                    }

                    continuation.yield(.started)

                    var buffer = [UInt8]()
                    var didEmitUsage = false
                    var toolArgsById: [String: String] = [:]
                    var toolNameById: [String: String] = [:]
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 10 {  // newline
                            let line =
                                String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(
                                    in: .whitespacesAndNewlines) ?? ""
                            buffer.removeAll()
                            if line.hasPrefix(":") { continue }  // commento SSE keep-alive
                            guard line.hasPrefix("data:") else { continue }
                            let jsonStr = line.dropFirst(5).trimmingCharacters(
                                in: .whitespaces)
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
                                return
                            }
                            guard let lineData = jsonStr.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: lineData)
                                    as? [String: Any]
                            else {
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
                                if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                    for toolCall in toolCalls {
                                        let id =
                                            (toolCall["id"] as? String)
                                            ?? "idx-\((toolCall["index"] as? Int).map(String.init) ?? "0")"
                                        if let function = toolCall["function"] as? [String: Any] {
                                            if let name = function["name"] as? String, !name.isEmpty
                                            {
                                                toolNameById[id] = name
                                            }
                                            if let argsFragment = function["arguments"] as? String,
                                                !argsFragment.isEmpty
                                            {
                                                toolArgsById[id, default: ""] += argsFragment
                                                continuation.yield(
                                                    .raw(
                                                        type: "tool_call_suggested",
                                                        payload: [
                                                            "id": id,
                                                            "name": toolNameById[id] ?? "",
                                                            "args_fragment": argsFragment,
                                                            "args": toolArgsById[id] ?? "",
                                                            "is_partial": "true",
                                                        ]))
                                            }
                                        }
                                    }
                                }
                                if let content = delta["content"] as? String, !content.isEmpty {
                                    continuation.yield(.textDelta(content))
                                }
                            }
                            if let finishReason = first["finish_reason"] as? String,
                                finishReason == "tool_calls"
                            {
                                for (id, args) in toolArgsById {
                                    continuation.yield(
                                        .raw(
                                            type: "tool_call_suggested",
                                            payload: [
                                                "id": id,
                                                "name": toolNameById[id] ?? "",
                                                "args": args,
                                                "is_partial": "false",
                                            ]))
                                }
                            }
                        }
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static var toolDefinitions: [[String: Any]] {
        [
            functionTool(
                name: "read",
                description:
                    "Read the content of a file. Always read a file before modifying it so you know its current state.",
                properties: [
                    "path": [
                        "type": "string",
                        "description":
                            "File path, absolute or workspace-relative (e.g. 'src/main.swift')",
                    ]
                ], required: ["path"]),
            functionTool(
                name: "ls",
                description:
                    "List the contents of a directory. Returns file and folder names (folders have a trailing /). Use this to explore project structure before reading files.",
                properties: [
                    "path": [
                        "type": "string",
                        "description":
                            "Directory path to list, absolute or workspace-relative. Defaults to '.' (workspace root).",
                    ]
                ], required: ["path"]),
            functionTool(
                name: "glob",
                description:
                    "Find files matching a glob pattern recursively. Useful for discovering files by extension or name pattern.",
                properties: [
                    "pattern": [
                        "type": "string",
                        "description": "Glob pattern to match, e.g. '*.swift', '*.ts', 'Package.*'",
                    ]
                ], required: ["pattern"]),
            functionTool(
                name: "grep",
                description:
                    "Search for text or regex patterns across files. Returns matching lines with file path, line number, and content. Uses ripgrep (rg) when available.",
                properties: [
                    "query": [
                        "type": "string", "description": "Text or regex pattern to search for",
                    ],
                    "pathScope": [
                        "type": "string",
                        "description":
                            "Optional folder or file scope to narrow the search (e.g. 'Sources', 'src/components')",
                    ],
                ], required: ["query"]),
            functionTool(
                name: "patch",
                description:
                    "Surgically edit a file by finding an exact text match and replacing it. PREFERRED over 'edit' for modifying existing files because it preserves all unchanged content. You MUST read the file first to get the exact text to search for.",
                properties: [
                    "path": ["type": "string", "description": "Target file path"],
                    "search": [
                        "type": "string",
                        "description":
                            "The exact text to find in the file (must match exactly, including whitespace and indentation)",
                    ],
                    "replace": ["type": "string", "description": "The replacement text"],
                ], required: ["path", "search", "replace"]),
            functionTool(
                name: "edit",
                description:
                    "Write the FULL content to a file, replacing everything. Creates parent directories if needed. Best for creating NEW files or complete rewrites. For modifying existing files, prefer 'patch' instead.",
                properties: [
                    "path": ["type": "string", "description": "Target file path"],
                    "content": [
                        "type": "string", "description": "The complete file content to write",
                    ],
                ], required: ["path", "content"]),
            functionTool(
                name: "bash",
                description:
                    "Run a shell command in the workspace directory. Use for builds, tests, git operations, installing packages, etc. Commands run in zsh with a 60-second timeout.",
                properties: [
                    "command": [
                        "type": "string",
                        "description":
                            "Shell command to execute (e.g. 'swift build 2>&1', 'npm test', 'git diff')",
                    ]
                ], required: ["command"]),
            functionTool(
                name: "mkdir",
                description: "Create a directory and all necessary parent directories.",
                properties: [
                    "path": ["type": "string", "description": "Directory path to create"]
                ], required: ["path"]),
            functionTool(
                name: "web_search",
                description:
                    "Search the web for information. Use when you need current documentation, API references, or solutions not in your training data.",
                properties: [
                    "query": ["type": "string", "description": "Search query"]
                ], required: ["query"]),
            functionTool(
                name: "mcp", description: "Invoke an MCP (Model Context Protocol) tool by name.",
                properties: [
                    "tool": ["type": "string", "description": "MCP tool name"],
                    "args": ["type": "string", "description": "JSON string of tool arguments"],
                ], required: ["tool"]),
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
