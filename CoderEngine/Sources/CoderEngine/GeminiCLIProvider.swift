import Foundation

/// Provider che usa Gemini CLI (`gemini`) con output `stream-json` per streaming reale.
public final class GeminiCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"

    private let geminiPath: String
    private let modelOverride: String?
    private let yoloMode: Bool
    private let approvalMode: String?
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        geminiPath: String? = nil,
        modelOverride: String? = nil,
        yoloMode: Bool = false,
        approvalMode: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        self.geminiPath =
            geminiPath ?? GeminiDetector.findGeminiPath(customPath: nil)
            ?? "/opt/homebrew/bin/gemini"
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.yoloMode = yoloMode
        self.approvalMode = approvalMode
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public func isAuthenticated() -> Bool {
        guard FileManager.default.fileExists(atPath: geminiPath) else { return false }
        return GeminiDetector.checkAuth(geminiPath: geminiPath)
    }

    private func shellEnvironment() -> [String: String] {
        var env = GeminiDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        return env
    }

    // MARK: - send

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        let fullPrompt = prompt + context.contextPrompt()
        let path = geminiPath
        let workspacePath = context.workspacePath

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(
                            .error(
                                "Gemini CLI non trovato a \(path). Installa con: npm install -g @anthropic-ai/gemini-cli"
                            ))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("gemini"))
                        return
                    }

                    let env = self.shellEnvironment()
                    var args: [String] = []

                    // Model
                    if let model = self.modelOverride, !model.isEmpty {
                        args += ["-m", model]
                    }

                    // Prompt (non-interactive headless mode)
                    args += ["-p", fullPrompt]

                    // Always use stream-json for real streaming
                    args += ["--output-format", "stream-json"]

                    // Approval / yolo mode
                    if self.yoloMode {
                        args += ["--yolo"]
                    } else if let approval = self.approvalMode, !approval.isEmpty {
                        args += ["--approval-mode", approval]
                    } else {
                        // Default: auto_edit (auto-approve edits, ask for dangerous commands)
                        args += ["--approval-mode", "auto_edit"]
                    }

                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: self.executionController,
                        scope: self.executionScope
                    )

                    continuation.yield(.started)
                    var accumulatedText = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var emittedMarkers = Set<String>()
                    // Track active tool calls for pairing tool_use → tool_result
                    var activeToolCalls: [String: [String: Any]] = [:]

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        else {
                            // Skip non-JSON lines (progress spinners, debug output, etc.)
                            continue
                        }

                        let eventType = json["type"] as? String ?? ""

                        switch eventType {

                        // ── init ──────────────────────────────────────────────
                        case "init":
                            // Session started – nothing to emit to UI
                            continue

                        // ── user message echo ─────────────────────────────────
                        case "message" where (json["role"] as? String) == "user":
                            continue

                        // ── assistant text delta ──────────────────────────────
                        case "message" where (json["role"] as? String) == "assistant":
                            if let content = json["content"] as? String, !content.isEmpty {
                                let isDelta = (json["delta"] as? Bool) == true
                                let textDelta: String
                                if isDelta {
                                    // stream-json sends incremental deltas
                                    textDelta = content
                                    accumulatedText += content
                                } else {
                                    // Fallback: full text (compute delta)
                                    if content.hasPrefix(accumulatedText) {
                                        textDelta = String(content.dropFirst(accumulatedText.count))
                                    } else {
                                        textDelta = content
                                    }
                                    accumulatedText = content
                                }

                                if !textDelta.isEmpty {
                                    continuation.yield(.textDelta(textDelta))

                                    // Check CoderIDE markers in accumulated text
                                    if !didEmitShowTaskPanel,
                                        accumulatedText.contains(CoderIDEMarkers.showTaskPanel)
                                    {
                                        didEmitShowTaskPanel = true
                                        continuation.yield(
                                            .raw(type: "coderide_show_task_panel", payload: [:]))
                                    }
                                    if !didEmitInvokeSwarm,
                                        accumulatedText.contains(CoderIDEMarkers.invokeSwarmPrefix),
                                        let start = accumulatedText.range(
                                            of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                                        let endRange = accumulatedText[start...].range(
                                            of: CoderIDEMarkers.invokeSwarmSuffix)
                                    {
                                        didEmitInvokeSwarm = true
                                        let task = String(
                                            accumulatedText[start..<endRange.lowerBound]
                                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !task.isEmpty {
                                            continuation.yield(
                                                .raw(
                                                    type: "coderide_invoke_swarm",
                                                    payload: ["task": task]))
                                        }
                                    }
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: textDelta)
                                    {
                                        let key =
                                            "\(markerEvent.type)|\(markerEvent.payload.description)"
                                        if emittedMarkers.insert(key).inserted {
                                            continuation.yield(
                                                .raw(
                                                    type: markerEvent.type,
                                                    payload: markerEvent.payload))
                                        }
                                    }
                                }
                            }

                        // ── tool_use: Gemini is invoking a tool ───────────────
                        case "tool_use":
                            let toolName = json["tool_name"] as? String ?? ""
                            let toolId = json["tool_id"] as? String ?? UUID().uuidString
                            let params = json["parameters"] as? [String: Any] ?? [:]
                            activeToolCalls[toolId] = json

                            let rawEvent = Self.buildToolUseEvent(
                                toolName: toolName, toolId: toolId, params: params)
                            continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))

                        // ── tool_result: tool finished ────────────────────────
                        case "tool_result":
                            let toolId = json["tool_id"] as? String ?? ""
                            let status = json["status"] as? String ?? "unknown"
                            let output = json["output"] as? String ?? ""
                            let useEvent = activeToolCalls.removeValue(forKey: toolId)

                            let rawEvent = Self.buildToolResultEvent(
                                toolId: toolId,
                                status: status,
                                output: output,
                                originalUse: useEvent
                            )
                            continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))

                        // ── result: final stats ───────────────────────────────
                        case "result":
                            if let stats = json["stats"] as? [String: Any] {
                                let input =
                                    (stats["input_tokens"] as? Int) ?? (stats["input"] as? Int)
                                    ?? -1
                                let output =
                                    (stats["output_tokens"] as? Int)
                                    ?? (stats["candidates"] as? Int) ?? -1
                                let total = (stats["total_tokens"] as? Int) ?? -1
                                let cached = (stats["cached"] as? Int) ?? 0
                                var usagePayload: [String: String] = [
                                    "input_tokens": "\(input)",
                                    "output_tokens": "\(output)",
                                    "model": "gemini-cli",
                                ]
                                if total > 0 { usagePayload["total_tokens"] = "\(total)" }
                                if cached > 0 { usagePayload["cached_tokens"] = "\(cached)" }
                                if let toolCalls = stats["tool_calls"] as? Int {
                                    usagePayload["tool_calls"] = "\(toolCalls)"
                                }
                                continuation.yield(.raw(type: "usage", payload: usagePayload))
                            }

                        // ── error event ───────────────────────────────────────
                        case "error":
                            let message =
                                (json["message"] as? String) ?? (json["error"] as? String)
                                ?? "Errore sconosciuto da Gemini CLI"
                            continuation.yield(.error(message))

                        // ── thinking/planning events ──────────────────────────
                        case "thinking", "planning":
                            // These are internal model events, skip
                            continue

                        // ── unknown event types: try to extract text ──────────
                        default:
                            // For any unrecognized event type, try extracting text
                            if let content = Self.extractTextFromAnyEvent(json), !content.isEmpty {
                                let delta: String
                                if content.hasPrefix(accumulatedText) {
                                    delta = String(content.dropFirst(accumulatedText.count))
                                    accumulatedText = content
                                } else if !accumulatedText.contains(content) {
                                    delta = content
                                    accumulatedText += content
                                } else {
                                    delta = ""
                                }
                                if !delta.isEmpty {
                                    continuation.yield(.textDelta(delta))
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

    // MARK: - Tool Event Builders

    /// Build a .raw event when Gemini begins using a tool
    private static func buildToolUseEvent(toolName: String, toolId: String, params: [String: Any])
        -> (type: String, payload: [String: String])
    {
        let normalizedName = toolName.lowercased()

        // Shell / bash commands
        if normalizedName.contains("shell") || normalizedName.contains("bash")
            || normalizedName.contains("command") || normalizedName.contains("terminal")
        {
            let command = stringParam(params, keys: ["command", "cmd", "command_line"]) ?? ""
            let description = stringParam(params, keys: ["description", "desc"]) ?? ""
            return (
                "command_execution",
                [
                    "title": "Bash",
                    "detail": description.isEmpty ? command : description,
                    "command": command,
                    "tool_id": toolId,
                    "status": "started",
                ]
            )
        }

        // File read
        if normalizedName.contains("read") && normalizedName.contains("file") {
            let path = stringParam(params, keys: ["path", "file_path", "file"]) ?? ""
            return (
                "read_batch_completed",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "files": path,
                    "count": "1",
                    "tool_id": toolId,
                    "status": "started",
                ]
            )
        }

        // File write/edit
        if normalizedName.contains("write") || normalizedName.contains("edit")
            || normalizedName.contains("create") || normalizedName.contains("replace")
            || normalizedName.contains("patch") || normalizedName.contains("update_file")
        {
            let path =
                stringParam(params, keys: ["path", "file_path", "file", "target_path"]) ?? "file"
            return (
                "file_change",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "tool_id": toolId,
                    "status": "started",
                ]
            )
        }

        // List / glob / search files
        if normalizedName.contains("list") || normalizedName.contains("glob")
            || normalizedName.contains("find") || normalizedName.contains("search")
        {
            let query =
                stringParam(
                    params, keys: ["pattern", "query", "path", "directory", "glob", "regex"]) ?? ""
            return (
                "read_batch_completed",
                [
                    "title": "Search • \(query)",
                    "detail": query,
                    "query": query,
                    "tool_id": toolId,
                    "status": "started",
                ]
            )
        }

        // Generic / unknown tool
        return (
            "mcp_tool_call",
            [
                "title": toolName,
                "detail": stringParam(params, keys: ["description", "desc"]) ?? toolName,
                "tool": toolName,
                "tool_id": toolId,
                "status": "started",
            ]
        )
    }

    /// Build a .raw event when a tool returns
    private static func buildToolResultEvent(
        toolId: String, status: String, output: String, originalUse: [String: Any]?
    ) -> (type: String, payload: [String: String]) {
        let toolName = (originalUse?["tool_name"] as? String) ?? ""
        let normalizedName = toolName.lowercased()
        let isSuccess = status == "success"
        let truncatedOutput = String(output.prefix(6_000))

        // Re-derive event type from original tool name
        if normalizedName.contains("shell") || normalizedName.contains("bash")
            || normalizedName.contains("command") || normalizedName.contains("terminal")
        {
            let params = originalUse?["parameters"] as? [String: Any] ?? [:]
            let command = stringParam(params, keys: ["command", "cmd", "command_line"]) ?? ""
            return (
                isSuccess ? "command_execution" : "tool_execution_error",
                [
                    "title": "Bash",
                    "detail": command,
                    "command": command,
                    "output": truncatedOutput,
                    "tool_id": toolId,
                    "status": isSuccess ? "completed" : "failed",
                ]
            )
        }

        if normalizedName.contains("read") && normalizedName.contains("file") {
            let params = originalUse?["parameters"] as? [String: Any] ?? [:]
            let path = stringParam(params, keys: ["path", "file_path", "file"]) ?? ""
            return (
                isSuccess ? "read_batch_completed" : "tool_execution_error",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "output": truncatedOutput,
                    "tool_id": toolId,
                    "status": isSuccess ? "completed" : "failed",
                ]
            )
        }

        if normalizedName.contains("write") || normalizedName.contains("edit")
            || normalizedName.contains("create") || normalizedName.contains("replace")
            || normalizedName.contains("patch") || normalizedName.contains("update_file")
        {
            let params = originalUse?["parameters"] as? [String: Any] ?? [:]
            let path =
                stringParam(params, keys: ["path", "file_path", "file", "target_path"]) ?? "file"
            return (
                isSuccess ? "file_change" : "tool_execution_error",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "output": truncatedOutput,
                    "tool_id": toolId,
                    "status": isSuccess ? "completed" : "failed",
                ]
            )
        }

        return (
            isSuccess ? "mcp_tool_call" : "tool_execution_error",
            [
                "title": toolName.isEmpty ? "Tool" : toolName,
                "detail": truncatedOutput,
                "tool": toolName,
                "output": truncatedOutput,
                "tool_id": toolId,
                "status": isSuccess ? "completed" : "failed",
            ]
        )
    }

    // MARK: - Text Extraction (fallback for unknown event types)

    private static func extractTextFromAnyEvent(_ json: [String: Any]) -> String? {
        // Try common text-bearing keys at top level
        for key in ["text", "content", "response", "result", "message", "output"] {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        // Try nested dicts
        for (key, value) in json {
            if key == "stats" || key == "parameters" || key == "type" || key == "timestamp" {
                continue
            }
            if let dict = value as? [String: Any] {
                if let found = extractTextFromAnyEvent(dict) { return found }
            }
            if let arr = value as? [[String: Any]] {
                let chunks = arr.compactMap { extractTextFromAnyEvent($0) }.filter { !$0.isEmpty }
                if !chunks.isEmpty { return chunks.joined(separator: "\n") }
            }
        }
        return nil
    }

    // MARK: - CoderIDE Marker Parsing

    private static func parseCoderIDEMarkerEvents(in text: String) -> [(
        type: String, payload: [String: String]
    )] {
        var events: [(type: String, payload: [String: String])] = []
        if text.contains(CoderIDEMarkers.todoRead) {
            events.append((type: "todo_read", payload: [:]))
        }
        events += parseMarkerList(
            text: text, prefix: CoderIDEMarkers.todoWritePrefix, mappedType: "todo_write")
        events += parseMarkerList(
            text: text, prefix: CoderIDEMarkers.instantGrepPrefix, mappedType: "instant_grep")
        events += parseMarkerList(
            text: text, prefix: CoderIDEMarkers.planStepPrefix, mappedType: "plan_step_update")
        events += parseMarkerList(
            text: text, prefix: CoderIDEMarkers.readBatchPrefix, mappedType: "read_batch_started")
        events += parseMarkerList(
            text: text, prefix: CoderIDEMarkers.webSearchPrefix, mappedType: "web_search_started")
        return events
    }

    private static func parseMarkerList(text: String, prefix: String, mappedType: String) -> [(
        type: String, payload: [String: String]
    )] {
        var events: [(type: String, payload: [String: String])] = []
        var searchRange: Range<String.Index>? = text.startIndex..<text.endIndex
        while let range = text.range(of: prefix, options: [], range: searchRange) {
            let payloadStart = range.upperBound
            guard let closing = text[payloadStart...].firstIndex(of: "]") else { break }
            let payloadString = String(text[payloadStart..<closing])
            let payload = parseMarkerPayload(payloadString)
            events.append((mappedType, payload))
            searchRange = closing..<text.endIndex
        }
        return events
    }

    private static func parseMarkerPayload(_ payload: String) -> [String: String] {
        var result: [String: String] = [:]
        for item in splitEscaped(payload, separator: "|") {
            let pair = splitEscaped(item, separator: "=")
            guard pair.count == 2 else { continue }
            result[unescapeMarker(pair[0]).trimmingCharacters(in: .whitespaces)] = unescapeMarker(
                pair[1]
            ).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func splitEscaped(_ input: String, separator: String) -> [String] {
        guard let separatorChar = separator.first else { return [input] }
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in input {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == separatorChar {
                parts.append(current)
                current.removeAll(keepingCapacity: true)
                continue
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    private static func unescapeMarker(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\]", with: "]")
    }

    // MARK: - Helpers

    private static func stringParam(_ params: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = params[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
