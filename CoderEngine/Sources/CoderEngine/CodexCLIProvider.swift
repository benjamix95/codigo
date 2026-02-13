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

    public init(codexPath: String? = nil, sandboxMode: CodexSandboxMode = .workspaceWrite, modelOverride: String? = nil, modelReasoningEffort: String? = nil, yoloMode: Bool = false) {
        self.codexPath = codexPath ?? PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.modelReasoningEffort = modelReasoningEffort?.isEmpty == true ? nil : modelReasoningEffort
        self.yoloMode = yoloMode
    }
    
    public func isAuthenticated() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "status"]
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func send(prompt: String, context: WorkspaceContext) async throws -> AsyncThrowingStream<StreamEvent, Error> {
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
                    
                    var args = [
                        "exec",
                        "--json",
                        "--full-auto",
                        "--sandbox", sandboxMode.rawValue,
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
                    
                    let stream = try await ProcessRunner.run(
                        executable: execPath,
                        arguments: args,
                        workingDirectory: workspacePath
                    )
                    
                    continuation.yield(.started)
                    var lastFullText = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        
                        // Emit .raw for structured task activities (file_change, command_execution, mcp_tool_call, web_search)
                        if let rawEvent = Self.parseRawEvent(from: json) {
                            continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
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
        let activityTypes = ["file_change", "command_execution", "mcp_tool_call", "web_search"]
        guard activityTypes.contains(type) else { return nil }
        
        var payload: [String: String] = ["title": titleForType(type, item: item), "detail": detailForType(type, item: item)]
        if let path = item["path"] as? String ?? item["file_path"] as? String { payload["path"] = path }
        if let path = item["path"] as? String { payload["file"] = path }
        if let cmd = item["command"] as? String ?? item["command_line"] as? String { payload["command"] = String(cmd.prefix(80)) }
        if let tool = item["tool"] as? String ?? item["name"] as? String { payload["tool"] = tool }
        if let added = item["additions"] as? Int { payload["linesAdded"] = "\(added)" }
        if let added = item["lines_added"] as? Int { payload["linesAdded"] = "\(added)" }
        if let removed = item["deletions"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let removed = item["lines_removed"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let query = item["query"] as? String { payload["query"] = query }
        if let edits = item["edit_count"] as? Int { payload["editCount"] = "\(edits)" }
        
        return (type, payload)
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
        default:
            return ""
        }
    }
}
