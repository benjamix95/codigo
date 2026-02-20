import Foundation

/// Modalità sandbox Codex: read-only, workspace-write, danger-full-access
public enum CodexSandboxMode: String, CaseIterable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

/// Marker che il modello può emettere per attivare il Task Activity Panel (formica)
public enum CoderIDEMarkers {
    public static let showTaskPanel = "[CODERIDE:show_task_panel]"
    public static let invokeSwarmPrefix = "[CODERIDE:invoke_swarm:"
    public static let invokeSwarmSuffix = "]"
    public static let todoWritePrefix = "[CODERIDE:todo_write|"
    public static let todoRead = "[CODERIDE:todo_read]"
    public static let instantGrepPrefix = "[CODERIDE:instant_grep|"
    public static let planStepPrefix = "[CODERIDE:plan_step|"
    public static let readBatchPrefix = "[CODERIDE:read_batch|"
    public static let webSearchPrefix = "[CODERIDE:web_search|"
}

/// Provider che usa Codex CLI (`codex exec`)
public final class CodexCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "codex-cli"
    public let displayName = "Codex CLI"
    
    private let codexPath: String
    private let sandboxMode: CodexSandboxMode
    private let modelOverride: String?
    private let modelReasoningEffort: String?
    private let yoloMode: Bool
    private let askForApproval: String
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(codexPath: String? = nil, sandboxMode: CodexSandboxMode = .workspaceWrite, modelOverride: String? = nil, modelReasoningEffort: String? = nil, yoloMode: Bool = false, askForApproval: String? = nil, executionController: ExecutionController? = nil, executionScope: ExecutionScope = .agent, environmentOverride: [String: String]? = nil) {
        self.codexPath = codexPath ?? PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.modelReasoningEffort = modelReasoningEffort?.isEmpty == true ? nil : modelReasoningEffort
        self.yoloMode = yoloMode
        self.askForApproval = Self.normalizeAskForApproval(askForApproval)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public static func normalizeAskForApproval(_ raw: String?) -> String {
        let allowed = Set(["never", "on-request", "untrusted"])
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "never"
        }

        while value.hasPrefix("-") {
            value.removeFirst()
        }

        if value == "ask-for-approval" {
            return "never"
        }
        return allowed.contains(value) ? value : "never"
    }
    
    public func isAuthenticated() -> Bool {
        if CodexDetector.hasAuthFile() { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "status"]
        process.standardOutput = nil
        process.standardError = nil
        var env = CodexDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        process.environment = env
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let path = codexPath
        let workspacePath = context.workspacePath
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let execPath = path
                    guard FileManager.default.fileExists(atPath: execPath) else {
                        continuation.yield(.error("Codex CLI non trovato a \(execPath). Installa con: brew install codex"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("codex"))
                        return
                    }
                    
                    var args: [String] = []
                    if let urls = imageURLs, !urls.isEmpty {
                        let paths = urls.map { $0.path }.joined(separator: ",")
                        args += ["exec", "--image", paths]
                    } else {
                        args += ["exec"]
                    }
                    args += ["--json"]
                    // Codex CLI non accetta --full-auto insieme a --yolo/--dangerously-bypass-approvals-and-sandbox.
                    if !yoloMode {
                        args += ["--full-auto"]
                    }
                    args += [
                        "--sandbox", sandboxMode.rawValue,
                        "-c", "approval_policy=\"\(askForApproval)\"",
                        "--cd", workspacePath.path,
                        fullPrompt
                    ]
                    if yoloMode {
                        args.insert("--yolo", at: args.count - 1)
                    }
                    if let model = modelOverride {
                        args.insert(contentsOf: ["--model", model], at: args.count - 1)
                    }
                    if let effort = modelReasoningEffort {
                        args.insert(contentsOf: ["-c", "model_reasoning_effort=\(effort)"], at: args.count - 1)
                    }
                    
                    var env = CodexDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }
                    let stream = try await ProcessRunner.run(
                        executable: execPath,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    var lastFullText = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var didEmitContextCompacted = false
                    var emittedMarkers = Set<String>()

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        
                        // Emit usage da turn.completed
                        if (json["type"] as? String) == "turn.completed",
                           let usage = json["usage"] as? [String: Any],
                           let inp = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int),
                           let out = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int) {
                            continuation.yield(.raw(type: "usage", payload: [
                                "input_tokens": "\(inp)",
                                "output_tokens": "\(out)",
                                "model": "codex"
                            ]))
                        }
                        // Emit .raw for structured task activities (file_change, command_execution, mcp_tool_call, web_search)
                        if let rawEvent = Self.parseRawEvent(from: json) {
                            continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                        }
                        if !didEmitContextCompacted, Self.containsCompactionSignal(json: json) {
                            didEmitContextCompacted = true
                            continuation.yield(.raw(type: "context_compacted", payload: [
                                "title": "Automatically compacting context",
                                "detail": "Codex ha compattato il contesto nativamente."
                            ]))
                        }
                        
                        func extractText(from obj: Any) -> String? {
                            if let dict = obj as? [String: Any] {
                                if let text = dict["text"] as? String { return text }
                                if let content = dict["content"] as? [[String: Any]] {
                                    return content.compactMap { extractText(from: $0) }.joined()
                                }
                                if let item = dict["item"] { return extractText(from: item) }
                                if let event = dict["event"] { return extractText(from: event) }
                            }
                            return nil
                        }
                        
                        if let text = extractText(from: json), !text.isEmpty {
                            if !didEmitShowTaskPanel, text.contains(CoderIDEMarkers.showTaskPanel) {
                                didEmitShowTaskPanel = true
                                continuation.yield(.raw(type: "coderide_show_task_panel", payload: [:]))
                            }
                            if !didEmitInvokeSwarm, text.contains(CoderIDEMarkers.invokeSwarmPrefix),
                               let start = text.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                               let endRange = text[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
                                didEmitInvokeSwarm = true
                                let task = String(text[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !task.isEmpty {
                                    continuation.yield(.raw(type: "coderide_invoke_swarm", payload: ["task": task]))
                                }
                            }
                            if text != lastFullText {
                                let delta = String(text.dropFirst(lastFullText.count))
                                lastFullText = text
                                if !delta.isEmpty {
                                    continuation.yield(.textDelta(delta))
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: delta) {
                                        let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                        if emittedMarkers.insert(key).inserted {
                                            continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
                                        }
                                    }
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
    
    /// Parses Codex JSONL for structured events (file_change, command_execution, mcp_tool_call, web_search)
    private static func parseRawEvent(from json: [String: Any]) -> (type: String, payload: [String: String])? {
        let item = (json["item"] as? [String: Any]) ?? json
        guard let type = (item["type"] as? String) ?? (json["type"] as? String) else { return nil }
        let activityTypes = ["file_change", "command_execution", "mcp_tool_call", "web_search", "instant_grep", "todo_write", "todo_read", "plan_step_update", "read_batch_started", "read_batch_completed", "web_search_started", "web_search_completed", "web_search_failed", "reasoning"]
        guard activityTypes.contains(type) else { return nil }
        
        var payload: [String: String] = ["title": titleForType(type, item: item), "detail": detailForType(type, item: item)]
        if let path = firstString(in: item, keys: ["path", "file_path", "file", "target_path"]) { payload["path"] = path }
        if let path = item["path"] as? String { payload["file"] = path }
        if let cmd = firstString(in: item, keys: ["command", "command_line", "cmd"]) { payload["command"] = cmd }
        if let cwd = firstString(in: item, keys: ["cwd", "working_directory", "workdir"]) { payload["cwd"] = cwd }
        if let output = firstString(in: item, keys: ["output", "result", "stdout", "message", "content", "text"]) {
            payload["output"] = String(output.prefix(6_000))
        }
        if let stderr = firstString(in: item, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
            payload["stderr"] = String(stderr.prefix(3_000))
        }
        if let tool = firstString(in: item, keys: ["tool", "name"]) { payload["tool"] = tool }
        if let added = item["additions"] as? Int { payload["linesAdded"] = "\(added)" }
        if let added = item["lines_added"] as? Int { payload["linesAdded"] = "\(added)" }
        if let removed = item["deletions"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let removed = item["lines_removed"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let query = firstString(in: item, keys: ["query", "search_query"]) { payload["query"] = query }
        if let qid = firstString(in: item, keys: ["query_id", "id"]) { payload["queryId"] = qid }
        if let status = firstString(in: item, keys: ["status"]) { payload["status"] = status }
        if let groupId = firstString(in: item, keys: ["group_id"]) { payload["group_id"] = groupId }
        if type == "reasoning" && payload["group_id"] == nil { payload["group_id"] = "reasoning-stream" }
        if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]) { payload["tool_call_id"] = toolCallId }
        if let count = item["result_count"] as? Int { payload["resultCount"] = "\(count)" }
        if let duration = item["duration_ms"] as? Int { payload["duration_ms"] = "\(duration)" }
        if let edits = item["edit_count"] as? Int { payload["editCount"] = "\(edits)" }
        
        return (type, payload)
    }

    private static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key] {
                if let stringValue = stringify(value), !stringValue.isEmpty {
                    return stringValue
                }
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

    private static func containsCompactionSignal(json: [String: Any]) -> Bool {
        if let item = json["item"] as? [String: Any],
           let itemType = item["type"] as? String,
           itemType.lowercased().contains("compaction") {
            return true
        }
        if let type = json["type"] as? String, type.lowercased().contains("compaction") {
            return true
        }
        // Fallback difensivo: intercetta eventuali payload text-based che includono la keyword.
        let payload = String(describing: json).lowercased()
        return payload.contains("compaction")
    }

    private static func parseCoderIDEMarkerEvents(in text: String) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []

        if text.contains(CoderIDEMarkers.todoRead) {
            events.append((type: "todo_read", payload: [:]))
        }

        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.todoWritePrefix, mappedType: "todo_write")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.instantGrepPrefix, mappedType: "instant_grep")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.planStepPrefix, mappedType: "plan_step_update")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.readBatchPrefix, mappedType: "read_batch_started")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.webSearchPrefix, mappedType: "web_search_started")

        return events
    }

    private static func parseMarkerList(text: String, prefix: String, mappedType: String) -> [(type: String, payload: [String: String])] {
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
            result[unescapeMarker(pair[0]).trimmingCharacters(in: .whitespaces)] = unescapeMarker(pair[1]).trimmingCharacters(in: .whitespaces)
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
    
    private static func titleForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            let path = (item["path"] as? String) ?? (item["file_path"] as? String) ?? "file"
            let base = (path as NSString).lastPathComponent
            let added = (item["additions"] as? Int) ?? (item["lines_added"] as? Int) ?? 0
            let removed = (item["deletions"] as? Int) ?? (item["lines_removed"] as? Int) ?? 0
            return "Edit • \(base) • +\(added) -\(removed) lines"
        case "command_execution":
            let cmd = (item["command"] as? String) ?? (item["command_line"] as? String) ?? "command"
            return "Bash • \(String(cmd.prefix(50)))..."
        case "mcp_tool_call":
            let tool = (item["tool"] as? String) ?? (item["name"] as? String) ?? "tool"
            return "\(tool)"
        case "web_search":
            return "Search"
        case "reasoning":
            let text = (item["text"] as? String) ?? (item["output"] as? String) ?? ""
            return text.isEmpty ? "Ragionamento" : String(text.prefix(60)) + (text.count > 60 ? "…" : "")
        default:
            return type
        }
    }
    
    private static func detailForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            let path = (item["path"] as? String) ?? (item["file_path"] as? String) ?? ""
            return path
        case "command_execution":
            return (item["command"] as? String) ?? (item["command_line"] as? String) ?? ""
        case "mcp_tool_call":
            return (item["query"] as? String) ?? (item["arguments"] as? String) ?? ""
        case "web_search":
            return (item["query"] as? String) ?? ""
        case "reasoning":
            return (item["text"] as? String) ?? (item["output"] as? String) ?? ""
        default:
            return ""
        }
    }
}
