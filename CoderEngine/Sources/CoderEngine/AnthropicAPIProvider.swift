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

    private static func supportsExtendedThinking(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("opus-4") || m.contains("sonnet-4") || m.contains("haiku-4")
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
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
                               let mediaType = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg") {
                                let b64 = data.base64EncodedString()
                                content.append([
                                    "type": "image",
                                    "source": ["type": "base64", "media_type": mediaType, "data": b64]
                                ])
                            }
                        }
                    }
                    content.append(["type": "text", "text": fullPrompt])

                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "system": SystemPrompts.taskCompletionStrict,
                        "tools": Self.toolDefinitions,
                        "messages": [
                            [
                                "role": "user",
                                "content": content
                            ]
                        ]
                    ]
                    if Self.supportsExtendedThinking(model) {
                        body["thinking"] = ["type": "enabled", "budget_tokens": 10_000]
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CoderEngineError.apiError("Anthropic API response non valida")
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw CoderEngineError.apiError("Anthropic API HTTP \(httpResponse.statusCode)")
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
                                    "is_partial": "false"
                                ]))
                            } else {
                                continuation.yield(.raw(type: "tool_call_suggested", payload: [
                                    "id": toolId,
                                    "name": toolName,
                                    "args": "",
                                    "is_partial": "true"
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
                                    "title": "Ragionamento",
                                    "group_id": "reasoning-stream"
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
                                    "is_partial": "true"
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
                                "is_partial": "false"
                            ]))
                        case "message_stop":
                            if let (inp, out) = lastUsage {
                                continuation.yield(.raw(type: "usage", payload: [
                                    "input_tokens": "\(inp)",
                                    "output_tokens": "\(out)",
                                    "model": model
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
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static var toolDefinitions: [[String: Any]] {
        [
            tool(name: "read", description: "Read file content from workspace", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path absolute or workspace-relative"]
                ],
                "required": ["path"]
            ]),
            tool(name: "glob", description: "Find files by pattern", schema: [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string", "description": "Pattern to match, e.g. *.swift"]
                ],
                "required": ["pattern"]
            ]),
            tool(name: "grep", description: "Search text in files", schema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Text/regex query"],
                    "pathScope": ["type": "string", "description": "Optional folder/file scope"]
                ],
                "required": ["query"]
            ]),
            tool(name: "edit", description: "Overwrite file with new content", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Target file path"],
                    "content": ["type": "string", "description": "Full file content to write"]
                ],
                "required": ["path", "content"]
            ]),
            tool(name: "write", description: "Alias of edit", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Target file path"],
                    "content": ["type": "string", "description": "Full file content to write"]
                ],
                "required": ["path", "content"]
            ]),
            tool(name: "bash", description: "Run shell command in workspace", schema: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Shell command"]
                ],
                "required": ["command"]
            ]),
            tool(name: "read_range", description: "Read a line range from a file", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Target file path"],
                    "start": ["type": "string", "description": "Start line (1-based)"],
                    "end": ["type": "string", "description": "End line (inclusive)"]
                ],
                "required": ["path", "start"]
            ]),
            tool(name: "list_dir", description: "List directory entries", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Directory path"],
                    "maxEntries": ["type": "string", "description": "Max number of entries"]
                ],
                "required": ["path"]
            ]),
            tool(name: "git_diff", description: "Show git diff", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Optional path scope"]
                ],
                "required": []
            ]),
            tool(name: "search_symbols", description: "Search code symbols", schema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Symbol query"],
                    "kind": ["type": "string", "description": "class|struct|enum|protocol|function|all"]
                ],
                "required": ["query"]
            ]),
            tool(name: "run_tests", description: "Run tests for the project", schema: [
                "type": "object",
                "properties": [
                    "target": ["type": "string", "description": "Optional test target or filter"],
                    "filter": ["type": "string", "description": "Optional test filter"],
                    "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
                ],
                "required": []
            ]),
            tool(name: "build_project", description: "Build the project", schema: [
                "type": "object",
                "properties": [
                    "configuration": ["type": "string", "description": "debug|release"],
                    "target": ["type": "string", "description": "Optional target"],
                    "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
                ],
                "required": []
            ]),
            tool(name: "list_processes", description: "List running processes", schema: [
                "type": "object",
                "properties": [
                    "filter": ["type": "string", "description": "Optional process filter"]
                ],
                "required": []
            ]),
            tool(name: "read_json", description: "Read and pretty-print JSON file", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "JSON file path"]
                ],
                "required": ["path"]
            ]),
            tool(name: "write_json", description: "Merge JSON patch into JSON file", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "JSON file path"],
                    "patch": ["type": "string", "description": "JSON object patch string"]
                ],
                "required": ["path", "patch"]
            ]),
            tool(name: "workspace_stats", description: "Collect workspace stats", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Optional relative path scope"]
                ],
                "required": []
            ]),
            tool(name: "dependency_audit", description: "Run dependency audit", schema: [
                "type": "object",
                "properties": [
                    "manager": ["type": "string", "description": "swift|npm|pnpm|yarn"]
                ],
                "required": []
            ]),
            tool(name: "tail_log", description: "Tail a log file", schema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Log file path"],
                    "lines": ["type": "string", "description": "Number of lines"]
                ],
                "required": ["path"]
            ]),
            tool(name: "mcp", description: "Invoke MCP tool", schema: [
                "type": "object",
                "properties": [
                    "tool": ["type": "string", "description": "MCP tool name"],
                    "args": ["type": "string", "description": "JSON string args"]
                ],
                "required": ["tool"]
            ]),
            tool(name: "mcp_list_servers", description: "List configured MCP servers", schema: [
                "type": "object",
                "properties": [:],
                "required": []
            ]),
            tool(name: "mcp_list_tools", description: "List MCP tools", schema: [
                "type": "object",
                "properties": [
                    "server": ["type": "string", "description": "Optional server id/name"]
                ],
                "required": []
            ]),
            tool(name: "mcp_describe_tool", description: "Describe MCP tool schema", schema: [
                "type": "object",
                "properties": [
                    "server": ["type": "string", "description": "Optional server id/name"],
                    "tool": ["type": "string", "description": "Tool name"]
                ],
                "required": ["tool"]
            ]),
            tool(name: "mcp_health", description: "Check MCP server health", schema: [
                "type": "object",
                "properties": [
                    "server": ["type": "string", "description": "Optional server id/name"]
                ],
                "required": []
            ]),
            tool(name: "mcp_reconnect", description: "Reconnect MCP session", schema: [
                "type": "object",
                "properties": [
                    "server": ["type": "string", "description": "Server id/name"]
                ],
                "required": ["server"]
            ]),
            tool(name: "web_search", description: "Search web", schema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ],
                "required": ["query"]
            ])
        ]
    }

    private static func tool(name: String, description: String, schema: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "input_schema": schema
        ]
    }
}
