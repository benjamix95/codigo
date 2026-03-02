import Foundation

/// Provider che usa Claude Code CLI (`claude -p`)
public final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "claude-cli"
    public let displayName = "Claude Code CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )
    
    private let claudePath: String
    private let model: String?
    private let allowedTools: [String]
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        claudePath: String? = nil,
        model: String? = nil,
        allowedTools: [String] = [],
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = claudePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.claudePath = candidate
        } else {
            self.claudePath = PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude"
        }
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
        self.allowedTools = Self.normalizeTools(allowedTools)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }
    
    public func isAuthenticated() -> Bool {
        let status = ClaudeDetector.detect(customPath: claudePath)
        return status.isInstalled && status.isLoggedIn
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemBlock = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        var fullPrompt = systemBlock + "\n\n" + prompt + context.contextPrompt()
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Image: \($0.path)]" }.joined(separator: "\n")
            fullPrompt = refs + "\n\n" + fullPrompt
        }
        let path = claudePath
        let workspacePath = context.workspacePath
        let model = self.model
        let allowedTools = self.allowedTools
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(.error("Claude CLI not found at \(path). Install it from https://claude.com/code"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("claude"))
                        return
                    }
                    
                    var args = [
                        "-p", fullPrompt,
                        "--output-format", "stream-json",
                        "--verbose"
                    ]
                    if let model {
                        args += ["--model", model]
                    }
                    if !allowedTools.isEmpty {
                        args += ["--allowedTools", allowedTools.joined(separator: ",")]
                    }
                    
                    var env = ClaudeDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }
                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    var fullContent = ""
                    var accumulatedThinking = ""
                    var lastUsageSignature = ""

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        if let usagePayload = Self.extractUsagePayload(from: json, defaultModel: model) {
                            let signature = [
                                usagePayload["model"] ?? "claude",
                                usagePayload["input_tokens"] ?? "0",
                                usagePayload["output_tokens"] ?? "0",
                            ].joined(separator: "|")
                            if signature != lastUsageSignature {
                                lastUsageSignature = signature
                                continuation.yield(.raw(type: "usage", payload: usagePayload))
                            }
                        }

                        let eventType = json["type"] as? String ?? ""

                        if eventType == "stream_event",
                           let event = json["event"] as? [String: Any],
                           let delta = event["delta"] as? [String: Any] {
                            if (delta["type"] as? String) == "thinking_delta",
                               let thinkingChunk = delta["thinking"] as? String, !thinkingChunk.isEmpty {
                                accumulatedThinking += thinkingChunk
                                let text = String(accumulatedThinking.prefix(6_000))
                                continuation.yield(.raw(type: "reasoning", payload: [
                                    "output": text,
                                    "title": "Reasoning",
                                    "group_id": "reasoning-stream"
                                ]))
                            }
                            if (delta["type"] as? String) == "text_delta",
                               let text = delta["text"] as? String {
                            fullContent += text
                            continuation.yield(.textDelta(text))
                            }
                        }

                        if eventType == "assistant", let message = json["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            for block in content {
                                if let rawEvent = Self.parseToolUse(from: block) {
                                    continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                                }
                                if (block["type"] as? String) == "thinking",
                                   let thinkingText = (block["thinking"] as? String) ?? (block["text"] as? String), !thinkingText.isEmpty {
                                    continuation.yield(.raw(type: "reasoning", payload: [
                                        "output": String(thinkingText.prefix(6_000)),
                                        "title": "Reasoning",
                                        "group_id": "reasoning-stream"
                                    ]))
                                }
                                if (block["type"] as? String) == "text", let text = block["text"] as? String, !text.isEmpty {
                                    if !fullContent.hasSuffix(text) {
                                        let newLen = fullContent.count
                                        fullContent += text
                                        let delta = String(fullContent.dropFirst(newLen))
                                        if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                                    }
                                }
                            }
                        }

                        if eventType == "result", let resultText = json["result"] as? String, !resultText.isEmpty {
                            if resultText.count > fullContent.count {
                                let delta = String(resultText.dropFirst(fullContent.count))
                                fullContent = resultText
                                continuation.yield(.textDelta(delta))
                            } else {
                                fullContent = resultText
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

    private static func parseToolUse(from block: [String: Any]) -> (type: String, payload: [String: String])? {
        guard (block["type"] as? String) == "tool_use",
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any] else { return nil }
        if let mapped = ProviderToolEventMapper.map(toolName: name, payload: input) {
            return mapped
        }

        // Smart fallback: infer event type from payload keys instead of always using command_execution
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(name)
        let hasPath = firstString(in: input, keys: ["path", "file_path", "file", "target_path"]) != nil
        let hasCommand = firstString(in: input, keys: ["command", "command_line", "cmd"]) != nil
        let hasQuery = firstString(in: input, keys: ["query", "pattern", "search", "needle"]) != nil
        let hasOldString = firstString(in: input, keys: ["old_string", "old_text"]) != nil
        let hasContent = firstString(in: input, keys: ["content", "new_string", "new_text"]) != nil

        // File change tools: have path + old_string/content modifications
        if hasPath && (hasOldString || (hasContent && !hasCommand)) {
            return ProviderToolEventMapper.map(toolName: "edit", payload: input, typeHint: "file_change")
        }
        // Read tools: have path but no modification keys and no command
        if hasPath && !hasCommand && !hasOldString && !hasContent {
            return ProviderToolEventMapper.map(toolName: "read", payload: input)
        }
        // Search tools: have query but no command
        if hasQuery && !hasCommand {
            return ProviderToolEventMapper.map(toolName: "search", payload: input)
        }

        // True fallback for genuinely unknown tools
        let fallbackTool = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ("command_execution", [
            "title": fallbackTool.isEmpty ? "Tool execution" : fallbackTool,
            "detail": firstString(in: input, keys: ["detail", "query", "command", "path", "file"]) ?? "",
            "tool": normalizedTool,
        ])
    }

    private static func normalizeTools(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        // Empty = no restriction → Claude CLI uses ALL available tools
        // (Read, Edit, Write, Bash, Glob, Grep, WebSearch, WebFetch,
        //  Task, TodoWrite, Skill, MCP, NotebookEdit, etc.)
        return result
    }

    private static func extractUsagePayload(
        from json: [String: Any],
        defaultModel: String?
    ) -> [String: String]? {
        guard let usage = extractUsageDictionary(from: json) else { return nil }
        let input = intValue(usage["input_tokens"])
            ?? intValue(usage["prompt_tokens"])
            ?? intValue(usage["input_token_count"])
            ?? 0
        let output = intValue(usage["output_tokens"])
            ?? intValue(usage["completion_tokens"])
            ?? intValue(usage["output_token_count"])
            ?? 0
        guard input > 0 || output > 0 else { return nil }

        let model = firstString(in: json, keys: ["model"])
            ?? defaultModel
            ?? "claude"

        return [
            "input_tokens": "\(input)",
            "output_tokens": "\(output)",
            "model": model,
        ]
    }

    private static func extractUsageDictionary(from json: [String: Any]) -> [String: Any]? {
        if let usage = json["usage"] as? [String: Any] {
            return usage
        }
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            return usage
        }
        if let event = json["event"] as? [String: Any] {
            if let usage = event["usage"] as? [String: Any] {
                return usage
            }
            if let delta = event["delta"] as? [String: Any],
               let usage = delta["usage"] as? [String: Any] {
                return usage
            }
        }
        if let result = json["result"] as? [String: Any],
           let usage = result["usage"] as? [String: Any] {
            return usage
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key], let stringValue = stringify(value), !stringValue.isEmpty {
                return stringValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstString(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstString(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private static func stringify(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [String] { return arr.joined(separator: "\n") }
        if let arr = value as? [[String: Any]] {
            let chunks = arr.compactMap { dict -> String? in
                if let t = dict["text"] as? String { return t }
                if let o = dict["output"] as? String { return o }
                return nil
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let o = dict["output"] as? String { return o }
            if let e = dict["error"] as? String { return e }
        }
        return nil
    }

    private static func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        let maxCount = min(max(oldLines.count, newLines.count), 80)
        for i in 0..<maxCount {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            if oldLine == newLine { continue }
            if let oldLine { out.append("- \(oldLine)") }
            if let newLine { out.append("+ \(newLine)") }
            if out.count >= 40 { break }
        }
        return out.joined(separator: "\n")
    }
}
