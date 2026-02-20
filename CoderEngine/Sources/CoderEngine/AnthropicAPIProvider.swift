import Foundation

/// Provider Anthropic Messages API con streaming SSE.
public final class AnthropicAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 4096,
        id: String = "anthropic-api",
        displayName: String = "Anthropic"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.id = id
        self.displayName = displayName
    }

    public func isAuthenticated() -> Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        let maxTokens = self.maxTokens

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                        throw CoderEngineError.apiError("Anthropic API URL non valida")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "accept")

                    var content: [[String: Any]] = []
                    if let urls = imageURLs, !urls.isEmpty {
                        for imgURL in urls {
                            if let data = try? Data(contentsOf: imgURL),
                                let ext = imgURL.pathExtension.lowercased() as String?,
                                let mediaType = ext == "png"
                                    ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                            {
                                let b64 = data.base64EncodedString()
                                content.append([
                                    "type": "image",
                                    "source": [
                                        "type": "base64", "media_type": mediaType, "data": b64,
                                    ],
                                ])
                            }
                        }
                    }
                    content.append(["type": "text", "text": fullPrompt])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "tools": Self.toolDefinitions,
                        "messages": [
                            [
                                "role": "user",
                                "content": content,
                            ]
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CoderEngineError.apiError("Anthropic API response non valida")
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw CoderEngineError.apiError(
                            "Anthropic API HTTP \(httpResponse.statusCode)")
                    }

                    continuation.yield(.started)

                    var lastUsage: (Int, Int)?
                    var toolIdByContentBlock: [Int: String] = [:]
                    var toolNameByContentBlock: [Int: String] = [:]
                    var toolArgsByContentBlock: [Int: String] = [:]
                    var buffer = [UInt8]()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte != 10 { continue }  // newline

                        let line =
                            String(bytes: buffer, encoding: .utf8)?
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
                            let json = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any],
                            let type = json["type"] as? String
                        else {
                            continue
                        }

                        switch type {
                        case "content_block_start":
                            guard let index = json["index"] as? Int,
                                let block = json["content_block"] as? [String: Any],
                                (block["type"] as? String) == "tool_use"
                            else { continue }

                            let toolId = (block["id"] as? String) ?? "anthropic-\(index)"
                            let toolName = (block["name"] as? String) ?? ""
                            toolIdByContentBlock[index] = toolId
                            toolNameByContentBlock[index] = toolName

                            if let input = block["input"],
                                JSONSerialization.isValidJSONObject(input),
                                let inputData = try? JSONSerialization.data(withJSONObject: input),
                                let inputJson = String(data: inputData, encoding: .utf8)
                            {
                                toolArgsByContentBlock[index] = inputJson
                                continuation.yield(
                                    .raw(
                                        type: "tool_call_suggested",
                                        payload: [
                                            "id": toolId,
                                            "name": toolName,
                                            "args": inputJson,
                                            "is_partial": "false",
                                        ]))
                            } else {
                                continuation.yield(
                                    .raw(
                                        type: "tool_call_suggested",
                                        payload: [
                                            "id": toolId,
                                            "name": toolName,
                                            "args": "",
                                            "is_partial": "true",
                                        ]))
                            }
                        case "content_block_delta":
                            guard let index = json["index"] as? Int,
                                let delta = json["delta"] as? [String: Any],
                                let deltaType = delta["type"] as? String
                            else { continue }

                            if deltaType == "text_delta" {
                                guard let text = delta["text"] as? String, !text.isEmpty else {
                                    continue
                                }
                                continuation.yield(.textDelta(text))
                                continue
                            }

                            if deltaType == "input_json_delta" {
                                let fragment = (delta["partial_json"] as? String) ?? ""
                                guard !fragment.isEmpty else { continue }
                                toolArgsByContentBlock[index, default: ""] += fragment
                                continuation.yield(
                                    .raw(
                                        type: "tool_call_suggested",
                                        payload: [
                                            "id": toolIdByContentBlock[index]
                                                ?? "anthropic-\(index)",
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
                                let out = usage["output_tokens"] as? Int
                            {
                                lastUsage = (inp, out)
                            }
                        case "content_block_stop":
                            guard let index = json["index"] as? Int,
                                let toolId = toolIdByContentBlock[index],
                                let toolName = toolNameByContentBlock[index]
                            else { continue }
                            continuation.yield(
                                .raw(
                                    type: "tool_call_suggested",
                                    payload: [
                                        "id": toolId,
                                        "name": toolName,
                                        "args": toolArgsByContentBlock[index] ?? "",
                                        "is_partial": "false",
                                    ]))
                        case "message_stop":
                            if let (inp, out) = lastUsage {
                                continuation.yield(
                                    .raw(
                                        type: "usage",
                                        payload: [
                                            "input_tokens": "\(inp)",
                                            "output_tokens": "\(out)",
                                            "model": model,
                                        ]))
                            }
                        case "error":
                            let errorPayload = json["error"] as? [String: Any]
                            let message =
                                errorPayload?["message"] as? String ?? "Anthropic API error"
                            continuation.yield(.error(message))
                        default:
                            continue
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
            tool(
                name: "read",
                description:
                    "Read the content of a file. Always read a file before modifying it so you know its current state.",
                schema: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description":
                                "File path, absolute or workspace-relative (e.g. 'src/main.swift')",
                        ]
                    ],
                    "required": ["path"],
                ]),
            tool(
                name: "ls",
                description:
                    "List the contents of a directory. Returns file and folder names (folders have a trailing /). Use this to explore project structure before reading files.",
                schema: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description":
                                "Directory path to list, absolute or workspace-relative. Defaults to '.' (workspace root).",
                        ]
                    ],
                    "required": ["path"],
                ]),
            tool(
                name: "glob",
                description:
                    "Find files matching a glob pattern recursively. Useful for discovering files by extension or name pattern.",
                schema: [
                    "type": "object",
                    "properties": [
                        "pattern": [
                            "type": "string",
                            "description":
                                "Glob pattern to match, e.g. '*.swift', '*.ts', 'Package.*'",
                        ]
                    ],
                    "required": ["pattern"],
                ]),
            tool(
                name: "grep",
                description:
                    "Search for text or regex patterns across files. Returns matching lines with file path, line number, and content. Uses ripgrep (rg) when available.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string", "description": "Text or regex pattern to search for",
                        ],
                        "pathScope": [
                            "type": "string",
                            "description":
                                "Optional folder or file scope to narrow the search (e.g. 'Sources', 'src/components')",
                        ],
                    ],
                    "required": ["query"],
                ]),
            tool(
                name: "patch",
                description:
                    "Surgically edit a file by finding an exact text match and replacing it. PREFERRED over 'edit' for modifying existing files because it preserves all unchanged content. You MUST read the file first to get the exact text to search for.",
                schema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Target file path"],
                        "search": [
                            "type": "string",
                            "description":
                                "The exact text to find in the file (must match exactly, including whitespace and indentation)",
                        ],
                        "replace": ["type": "string", "description": "The replacement text"],
                    ],
                    "required": ["path", "search", "replace"],
                ]),
            tool(
                name: "edit",
                description:
                    "Write the FULL content to a file, replacing everything. Creates parent directories if needed. Best for creating NEW files or complete rewrites. For modifying existing files, prefer 'patch' instead.",
                schema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Target file path"],
                        "content": [
                            "type": "string", "description": "The complete file content to write",
                        ],
                    ],
                    "required": ["path", "content"],
                ]),
            tool(
                name: "bash",
                description:
                    "Run a shell command in the workspace directory. Use for builds, tests, git operations, installing packages, etc. Commands run in zsh with a 60-second timeout.",
                schema: [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description":
                                "Shell command to execute (e.g. 'swift build 2>&1', 'npm test', 'git diff')",
                        ]
                    ],
                    "required": ["command"],
                ]),
            tool(
                name: "mkdir",
                description: "Create a directory and all necessary parent directories.",
                schema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Directory path to create"]
                    ],
                    "required": ["path"],
                ]),
            tool(
                name: "web_search",
                description:
                    "Search the web for information. Use when you need current documentation, API references, or solutions not in your training data.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query"]
                    ],
                    "required": ["query"],
                ]),
            tool(
                name: "mcp", description: "Invoke an MCP (Model Context Protocol) tool by name.",
                schema: [
                    "type": "object",
                    "properties": [
                        "tool": ["type": "string", "description": "MCP tool name"],
                        "args": ["type": "string", "description": "JSON string of tool arguments"],
                    ],
                    "required": ["tool"],
                ]),
        ]
    }

    private static func tool(name: String, description: String, schema: [String: Any]) -> [String:
        Any]
    {
        [
            "name": name,
            "description": description,
            "input_schema": schema,
        ]
    }
}
