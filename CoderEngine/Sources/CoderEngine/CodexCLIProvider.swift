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

/// Parametri per creare un CodexCLIProvider (usato da PlanMode e Swarm)
public struct CodexCreateParams: Sendable {
    public let codexPath: String?
    public let sandboxMode: CodexSandboxMode
    public let modelOverride: String?
    public let modelReasoningEffort: String?
    public let askForApproval: String

    public init(
        codexPath: String? = nil,
        sandboxMode: CodexSandboxMode = .workspaceWrite,
        modelOverride: String? = nil,
        modelReasoningEffort: String? = nil,
        askForApproval: String = "never"
    ) {
        self.codexPath = codexPath
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride
        self.modelReasoningEffort = modelReasoningEffort
        self.askForApproval = askForApproval
    }
}

/// Provider che usa Codex CLI (`codex exec --json`)
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

    public init(
        codexPath: String? = nil,
        sandboxMode: CodexSandboxMode = .workspaceWrite,
        modelOverride: String? = nil,
        modelReasoningEffort: String? = nil,
        yoloMode: Bool = false,
        askForApproval: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        self.codexPath = codexPath ?? PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.modelReasoningEffort =
            modelReasoningEffort?.isEmpty == true ? nil : modelReasoningEffort
        self.yoloMode = yoloMode
        self.askForApproval = Self.normalizeAskForApproval(askForApproval)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    // MARK: - Public Helpers

    public static func normalizeAskForApproval(_ raw: String?) -> String {
        let allowed = Set(["never", "on-request", "untrusted"])
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else {
            return "never"
        }
        while value.hasPrefix("-") { value.removeFirst() }
        if value == "ask-for-approval" { return "never" }
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

    // MARK: - send

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let path = codexPath
        let workspacePath = context.workspacePath

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(
                            .error(
                                "Codex CLI non trovato a \(path). Installa con: brew install codex")
                        )
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
                    // Codex CLI non accetta --full-auto insieme a --yolo
                    if !self.yoloMode {
                        args += ["--full-auto"]
                    }
                    args += [
                        "--sandbox", self.sandboxMode.rawValue,
                        "--cd", workspacePath.path,
                        fullPrompt,
                    ]
                    if self.yoloMode {
                        args.insert("--yolo", at: args.count - 1)
                    }
                    if let model = self.modelOverride {
                        args.insert(contentsOf: ["--model", model], at: args.count - 1)
                    }
                    if let effort = self.modelReasoningEffort {
                        args.insert(
                            contentsOf: ["-c", "model_reasoning_effort=\(effort)"],
                            at: args.count - 1)
                    }

                    var env = CodexDetector.shellEnvironment()
                    if let override = self.environmentOverride {
                        env.merge(override) { _, new in new }
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
                    var lastFullText = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var didEmitContextCompacted = false
                    var emittedMarkers = Set<String>()
                    // Track active function calls by call_id for pairing call → output
                    var activeFunctionCalls: [String: [String: Any]] = [:]

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        else {
                            continue
                        }

                        let eventType = json["type"] as? String ?? ""

                        // ── Usage from turn.completed ────────────────────────
                        if eventType == "turn.completed" {
                            if let usage = json["usage"] as? [String: Any] {
                                let inp =
                                    (usage["input_tokens"] as? Int)
                                    ?? (usage["prompt_tokens"] as? Int) ?? -1
                                let out =
                                    (usage["output_tokens"] as? Int)
                                    ?? (usage["completion_tokens"] as? Int) ?? -1
                                continuation.yield(
                                    .raw(
                                        type: "usage",
                                        payload: [
                                            "input_tokens": "\(inp)",
                                            "output_tokens": "\(out)",
                                            "model": "codex",
                                        ]))
                            }
                        }

                        // ── Context compaction detection ─────────────────────
                        if !didEmitContextCompacted, Self.containsCompactionSignal(json: json) {
                            didEmitContextCompacted = true
                            continuation.yield(
                                .raw(
                                    type: "context_compacted",
                                    payload: [
                                        "title": "Automatically compacting context",
                                        "detail": "Codex ha compattato il contesto nativamente.",
                                    ]))
                        }

                        // ── Error events ─────────────────────────────────────
                        if eventType == "error" || eventType == "turn.failed" {
                            let message = Self.extractErrorMessage(from: json) ?? "Errore Codex CLI"
                            continuation.yield(.error(message))
                        }

                        // ── Emit structured tool activity events ─────────────
                        let toolEvents = Self.parseToolEvents(
                            json: json,
                            eventType: eventType,
                            activeCalls: &activeFunctionCalls
                        )
                        for toolEvent in toolEvents {
                            continuation.yield(
                                .raw(type: toolEvent.type, payload: toolEvent.payload))
                        }

                        // ── Legacy parseRawEvent for direct activity types ───
                        if let rawEvent = Self.parseLegacyRawEvent(from: json) {
                            continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                        }

                        // ── Text extraction ──────────────────────────────────
                        if let text = Self.extractText(from: json), !text.isEmpty {
                            // Check CoderIDE markers in accumulated text
                            let projected =
                                lastFullText + (text.hasPrefix(lastFullText) ? "" : text)
                            if !didEmitShowTaskPanel,
                                projected.contains(CoderIDEMarkers.showTaskPanel)
                            {
                                didEmitShowTaskPanel = true
                                continuation.yield(
                                    .raw(type: "coderide_show_task_panel", payload: [:]))
                            }
                            if !didEmitInvokeSwarm,
                                projected.contains(CoderIDEMarkers.invokeSwarmPrefix),
                                let start = projected.range(of: CoderIDEMarkers.invokeSwarmPrefix)?
                                    .upperBound,
                                let endRange = projected[start...].range(
                                    of: CoderIDEMarkers.invokeSwarmSuffix)
                            {
                                didEmitInvokeSwarm = true
                                let task = String(projected[start..<endRange.lowerBound])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !task.isEmpty {
                                    continuation.yield(
                                        .raw(type: "coderide_invoke_swarm", payload: ["task": task])
                                    )
                                }
                            }

                            // Compute delta
                            if text != lastFullText {
                                let delta: String
                                if text.hasPrefix(lastFullText) {
                                    delta = String(text.dropFirst(lastFullText.count))
                                } else if lastFullText.isEmpty {
                                    delta = text
                                } else {
                                    // Text was replaced (e.g. new turn) – emit as new chunk
                                    delta = text
                                }
                                lastFullText = text
                                if !delta.isEmpty {
                                    continuation.yield(.textDelta(delta))
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: delta) {
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
                        }

                        // ── Handle text delta events directly ────────────────
                        // Some Codex versions emit {"type":"message.output_text.delta","delta":"..."}
                        if let directDelta = Self.extractDirectDelta(
                            from: json, eventType: eventType)
                        {
                            lastFullText += directDelta
                            continuation.yield(.textDelta(directDelta))
                            for markerEvent in Self.parseCoderIDEMarkerEvents(in: directDelta) {
                                let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                if emittedMarkers.insert(key).inserted {
                                    continuation.yield(
                                        .raw(type: markerEvent.type, payload: markerEvent.payload))
                                }
                            }
                            // Re-check markers on accumulated text
                            if !didEmitShowTaskPanel,
                                lastFullText.contains(CoderIDEMarkers.showTaskPanel)
                            {
                                didEmitShowTaskPanel = true
                                continuation.yield(
                                    .raw(type: "coderide_show_task_panel", payload: [:]))
                            }
                            if !didEmitInvokeSwarm,
                                lastFullText.contains(CoderIDEMarkers.invokeSwarmPrefix),
                                let start = lastFullText.range(
                                    of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                                let endRange = lastFullText[start...].range(
                                    of: CoderIDEMarkers.invokeSwarmSuffix)
                            {
                                didEmitInvokeSwarm = true
                                let task = String(lastFullText[start..<endRange.lowerBound])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !task.isEmpty {
                                    continuation.yield(
                                        .raw(type: "coderide_invoke_swarm", payload: ["task": task])
                                    )
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

    // MARK: - Tool Event Parsing (new Codex JSONL format)

    /// Parses all known Codex JSONL event types and returns mapped app events.
    /// Handles: item.created (function_call / function_call_output / message),
    ///          tool.run / tool.done, response.output_item.added / .done,
    ///          response.function_call_arguments.done, etc.
    private static func parseToolEvents(
        json: [String: Any],
        eventType: String,
        activeCalls: inout [String: [String: Any]]
    ) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []

        switch eventType {

        // ── item.created ──────────────────────────────────────────────────
        // Codex emits item.created with item.type = "function_call" when starting a tool
        // and item.type = "function_call_output" when a tool returns.
        case "item.created":
            guard let item = json["item"] as? [String: Any],
                let itemType = item["type"] as? String
            else { break }

            if itemType == "function_call" {
                let callId =
                    (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
                let name = (item["name"] as? String) ?? ""
                activeCalls[callId] = item
                if let event = buildToolStartEvent(name: name, item: item, callId: callId) {
                    events.append(event)
                }
            } else if itemType == "function_call_output" {
                let callId = (item["call_id"] as? String) ?? ""
                let output = (item["output"] as? String) ?? ""
                let original = activeCalls.removeValue(forKey: callId)
                let originalName = (original?["name"] as? String) ?? ""
                if let event = buildToolDoneEvent(
                    name: originalName, output: output, callId: callId, original: original)
                {
                    events.append(event)
                }
            }

        // ── response.output_item.added / response.output_item.done ───────
        // Alternative format where Codex wraps items in response events
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
                let itemType = item["type"] as? String,
                itemType == "function_call"
            {
                let callId =
                    (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
                let name = (item["name"] as? String) ?? ""
                activeCalls[callId] = item
                if let event = buildToolStartEvent(name: name, item: item, callId: callId) {
                    events.append(event)
                }
            }

        case "response.output_item.done":
            if let item = json["item"] as? [String: Any],
                let itemType = item["type"] as? String
            {
                if itemType == "function_call" {
                    let callId = (item["call_id"] as? String) ?? (item["id"] as? String) ?? ""
                    let name = (item["name"] as? String) ?? ""
                    // Extract arguments for display
                    let argsStr = (item["arguments"] as? String) ?? ""
                    let argsDict = parseJsonArgs(argsStr)
                    var payload: [String: String] = [
                        "tool_id": callId,
                        "status": "started",
                    ]
                    if name == "shell" || name == "bash" || name == "container.exec" {
                        let cmd = argsDict["command"] ?? argsDict["cmd"] ?? argsStr
                        payload["title"] = "Bash"
                        payload["detail"] = String(cmd.prefix(200))
                        payload["command"] = cmd
                        events.append(("command_execution", payload))
                    } else if name == "file_write" || name == "write" || name == "create_file"
                        || name == "apply_diff" || name == "edit" || name == "apply_patch"
                    {
                        let path = argsDict["path"] ?? argsDict["file_path"] ?? "file"
                        payload["title"] = "Edit • \((path as NSString).lastPathComponent)"
                        payload["detail"] = path
                        payload["path"] = path
                        payload["file"] = path
                        events.append(("file_change", payload))
                    } else if name == "file_read" || name == "read" || name == "read_file" {
                        let path = argsDict["path"] ?? argsDict["file_path"] ?? ""
                        if !path.isEmpty {
                            payload["title"] = "Read • \((path as NSString).lastPathComponent)"
                            payload["detail"] = path
                            payload["path"] = path
                            payload["file"] = path
                            payload["files"] = path
                            payload["count"] = "1"
                            events.append(("read_batch_completed", payload))
                        }
                    }
                    activeCalls[callId] = item
                } else if itemType == "function_call_output" {
                    let callId = (item["call_id"] as? String) ?? ""
                    let output = (item["output"] as? String) ?? ""
                    let original = activeCalls.removeValue(forKey: callId)
                    let originalName = (original?["name"] as? String) ?? ""
                    if let event = buildToolDoneEvent(
                        name: originalName, output: output, callId: callId, original: original)
                    {
                        events.append(event)
                    }
                }
            }

        // ── response.function_call_arguments.done ────────────────────────
        // Final arguments for a function call (some Codex versions emit this)
        case "response.function_call_arguments.done":
            let callId = (json["call_id"] as? String) ?? (json["item_id"] as? String) ?? ""
            let argsStr = (json["arguments"] as? String) ?? ""
            let name = (json["name"] as? String) ?? (activeCalls[callId]?["name"] as? String) ?? ""
            let argsDict = parseJsonArgs(argsStr)
            // Update active call with parsed args
            if !callId.isEmpty {
                var existing = activeCalls[callId] ?? [:]
                existing["arguments"] = argsStr
                existing["name"] = name
                activeCalls[callId] = existing
            }
            // Emit a start event if we haven't yet
            if let event = buildToolStartEvent(name: name, argsDict: argsDict, callId: callId) {
                events.append(event)
            }

        // ── tool.run / tool.done ─────────────────────────────────────────
        // Some Codex versions use this simpler format
        case "tool.run":
            let toolType = (json["tool_type"] as? String) ?? ""
            let callId =
                (json["id"] as? String) ?? (json["call_id"] as? String) ?? UUID().uuidString
            activeCalls[callId] = json
            if let event = buildToolRunEvent(toolType: toolType, json: json, callId: callId) {
                events.append(event)
            }

        case "tool.done":
            let toolType = (json["tool_type"] as? String) ?? ""
            let callId = (json["id"] as? String) ?? (json["call_id"] as? String) ?? ""
            let original = activeCalls.removeValue(forKey: callId)
            if let event = buildToolDoneFromRun(
                toolType: toolType, json: json, callId: callId, original: original)
            {
                events.append(event)
            }

        // ── codex_cli.tool_start / codex_cli.tool_end ────────────────────
        // Yet another variant
        case "codex_cli.tool_start", "tool_start":
            let name = (json["name"] as? String) ?? (json["tool"] as? String) ?? ""
            let callId = (json["id"] as? String) ?? UUID().uuidString
            activeCalls[callId] = json
            let argsDict: [String: String]
            if let params = json["parameters"] as? [String: Any] {
                argsDict = params.compactMapValues { $0 as? String }
            } else if let argsStr = json["arguments"] as? String {
                argsDict = parseJsonArgs(argsStr)
            } else {
                argsDict = [:]
            }
            if let event = buildToolStartEvent(name: name, argsDict: argsDict, callId: callId) {
                events.append(event)
            }

        case "codex_cli.tool_end", "tool_end":
            let callId = (json["id"] as? String) ?? ""
            let output = (json["output"] as? String) ?? (json["result"] as? String) ?? ""
            let original = activeCalls.removeValue(forKey: callId)
            let name = (original?["name"] as? String) ?? (json["name"] as? String) ?? ""
            if let event = buildToolDoneEvent(
                name: name, output: output, callId: callId, original: original)
            {
                events.append(event)
            }

        default:
            break
        }

        return events
    }

    // MARK: - Tool Event Builders

    /// Build a "started" event from a function call name + item dict
    private static func buildToolStartEvent(
        name: String,
        item: [String: Any] = [:],
        callId: String
    ) -> (type: String, payload: [String: String])? {
        let argsStr = (item["arguments"] as? String) ?? ""
        let argsDict = parseJsonArgs(argsStr)
        return buildToolStartEvent(name: name, argsDict: argsDict, callId: callId)
    }

    /// Build a "started" event from a function call name + parsed args
    private static func buildToolStartEvent(
        name: String,
        argsDict: [String: String],
        callId: String
    ) -> (type: String, payload: [String: String])? {
        let normalized = name.lowercased()

        // Shell / bash / container exec
        if normalized == "shell" || normalized == "bash" || normalized.contains("exec")
            || normalized.contains("terminal") || normalized.contains("command")
        {
            let cmd = argsDict["command"] ?? argsDict["cmd"] ?? ""
            return (
                "command_execution",
                [
                    "title": "Bash",
                    "detail": String(cmd.prefix(200)),
                    "command": cmd,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // File write / edit / patch / diff
        if normalized == "file_write" || normalized == "write" || normalized == "create_file"
            || normalized == "edit" || normalized == "apply_diff" || normalized == "apply_patch"
            || normalized == "write_file" || normalized == "update_file"
            || normalized == "patch" || normalized == "replace_in_file"
        {
            let path =
                argsDict["path"] ?? argsDict["file_path"] ?? argsDict["target_path"] ?? "file"
            return (
                "file_change",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // File read
        if normalized == "file_read" || normalized == "read" || normalized == "read_file" {
            let path = argsDict["path"] ?? argsDict["file_path"] ?? ""
            guard !path.isEmpty else { return nil }
            return (
                "read_batch_completed",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "files": path,
                    "count": "1",
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // List / glob / find / search
        if normalized == "list_dir" || normalized == "ls" || normalized == "glob"
            || normalized == "find" || normalized == "list_directory"
            || normalized == "directory_tree"
        {
            let target = argsDict["path"] ?? argsDict["pattern"] ?? argsDict["directory"] ?? "."
            return (
                "read_batch_completed",
                [
                    "title": "List • \(target)",
                    "detail": target,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // Grep / search
        if normalized == "grep" || normalized == "search" || normalized == "rg"
            || normalized == "text_search" || normalized == "code_search"
        {
            let query = argsDict["query"] ?? argsDict["pattern"] ?? argsDict["regex"] ?? ""
            return (
                "instant_grep",
                [
                    "title": "Grep • \(query)",
                    "detail": query,
                    "query": query,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // Web search
        if normalized.contains("web_search") || normalized.contains("search_web")
            || normalized.contains("browser")
        {
            let query = argsDict["query"] ?? argsDict["search_query"] ?? ""
            return (
                "web_search_started",
                [
                    "title": "Web Search",
                    "detail": query,
                    "query": query,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // MCP tool
        if normalized == "mcp" || normalized.hasPrefix("mcp_") || normalized.contains("mcp") {
            let tool = argsDict["tool"] ?? argsDict["name"] ?? name
            return (
                "mcp_tool_call",
                [
                    "title": tool,
                    "detail": argsDict["query"] ?? argsDict["arguments"] ?? "",
                    "tool": tool,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        // Generic / unknown tool — still emit for TaskActivityPanel
        if !name.isEmpty {
            return (
                "mcp_tool_call",
                [
                    "title": name,
                    "detail": argsDict.values.joined(separator: " ").prefix(200).description,
                    "tool": name,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }

        return nil
    }

    /// Build a "completed" event when a function call returns
    private static func buildToolDoneEvent(
        name: String,
        output: String,
        callId: String,
        original: [String: Any]?
    ) -> (type: String, payload: [String: String])? {
        let normalized = name.lowercased()
        let truncated = String(output.prefix(6_000))

        // Re-derive event type from original function name
        if normalized == "shell" || normalized == "bash" || normalized.contains("exec")
            || normalized.contains("terminal") || normalized.contains("command")
        {
            let cmd: String
            if let orig = original {
                let argsStr = (orig["arguments"] as? String) ?? ""
                let argsDict = parseJsonArgs(argsStr)
                cmd = argsDict["command"] ?? argsDict["cmd"] ?? ""
            } else {
                cmd = ""
            }
            return (
                "command_execution",
                [
                    "title": "Bash",
                    "detail": cmd.isEmpty ? truncated : String(cmd.prefix(200)),
                    "command": cmd,
                    "output": truncated,
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }

        if normalized == "file_write" || normalized == "write" || normalized == "create_file"
            || normalized == "edit" || normalized == "apply_diff" || normalized == "apply_patch"
            || normalized == "write_file" || normalized == "update_file"
            || normalized == "patch" || normalized == "replace_in_file"
        {
            let path: String
            if let orig = original {
                let argsStr = (orig["arguments"] as? String) ?? ""
                let argsDict = parseJsonArgs(argsStr)
                path =
                    argsDict["path"] ?? argsDict["file_path"] ?? argsDict["target_path"] ?? "file"
            } else {
                path = "file"
            }
            return (
                "file_change",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "output": truncated,
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }

        if normalized == "file_read" || normalized == "read" || normalized == "read_file" {
            let path: String
            if let orig = original {
                let argsStr = (orig["arguments"] as? String) ?? ""
                let argsDict = parseJsonArgs(argsStr)
                path = argsDict["path"] ?? argsDict["file_path"] ?? ""
            } else {
                path = ""
            }
            return (
                "read_batch_completed",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "files": path,
                    "count": "1",
                    "output": truncated,
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }

        // Generic completed tool
        if !name.isEmpty {
            return (
                "mcp_tool_call",
                [
                    "title": name,
                    "detail": truncated,
                    "tool": name,
                    "output": truncated,
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }

        return nil
    }

    /// Build a "started" event from tool.run format
    private static func buildToolRunEvent(
        toolType: String,
        json: [String: Any],
        callId: String
    ) -> (type: String, payload: [String: String])? {
        let normalized = toolType.lowercased()
        if normalized == "shell" || normalized == "bash" {
            let shellData = (json["shell"] as? [String: Any]) ?? json
            let cmd = (shellData["command"] as? String) ?? ""
            return (
                "command_execution",
                [
                    "title": "Bash",
                    "detail": String(cmd.prefix(200)),
                    "command": cmd,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }
        if normalized == "file_write" || normalized == "write" {
            let writeData = (json["file_write"] as? [String: Any]) ?? json
            let path =
                (writeData["path"] as? String) ?? (writeData["file_path"] as? String) ?? "file"
            return (
                "file_change",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }
        if normalized == "file_read" || normalized == "read" {
            let readData = (json["file_read"] as? [String: Any]) ?? json
            let path = (readData["path"] as? String) ?? (readData["file_path"] as? String) ?? ""
            guard !path.isEmpty else { return nil }
            return (
                "read_batch_completed",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "files": path,
                    "count": "1",
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }
        // Generic tool.run
        if !toolType.isEmpty {
            return (
                "mcp_tool_call",
                [
                    "title": toolType,
                    "detail": "",
                    "tool": toolType,
                    "tool_id": callId,
                    "status": "started",
                ]
            )
        }
        return nil
    }

    /// Build a "completed" event from tool.done format
    private static func buildToolDoneFromRun(
        toolType: String,
        json: [String: Any],
        callId: String,
        original: [String: Any]?
    ) -> (type: String, payload: [String: String])? {
        let normalized = toolType.lowercased()
        if normalized == "shell" || normalized == "bash" {
            let shellData = (json["shell"] as? [String: Any]) ?? json
            let cmd =
                (shellData["command"] as? String)
                ?? ((original?["shell"] as? [String: Any])?["command"] as? String)
                ?? ""
            let output = (shellData["output"] as? String) ?? (shellData["stdout"] as? String) ?? ""
            let exitCode = (shellData["exit_code"] as? Int) ?? 0
            return (
                "command_execution",
                [
                    "title": "Bash",
                    "detail": cmd.isEmpty ? String(output.prefix(200)) : String(cmd.prefix(200)),
                    "command": cmd,
                    "output": String(output.prefix(6_000)),
                    "exit_code": "\(exitCode)",
                    "tool_id": callId,
                    "status": exitCode == 0 ? "completed" : "failed",
                ]
            )
        }
        if normalized == "file_write" || normalized == "write" {
            let writeData = (json["file_write"] as? [String: Any]) ?? json
            let origWriteData = (original?["file_write"] as? [String: Any]) ?? (original ?? [:])
            let path =
                (writeData["path"] as? String)
                ?? (origWriteData["path"] as? String) ?? "file"
            return (
                "file_change",
                [
                    "title": "Edit • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }
        if normalized == "file_read" || normalized == "read" {
            let readData = (json["file_read"] as? [String: Any]) ?? json
            let origReadData = (original?["file_read"] as? [String: Any]) ?? (original ?? [:])
            let path =
                (readData["path"] as? String)
                ?? (origReadData["path"] as? String) ?? ""
            let output = (readData["output"] as? String) ?? (readData["content"] as? String) ?? ""
            return (
                "read_batch_completed",
                [
                    "title": "Read • \((path as NSString).lastPathComponent)",
                    "detail": path,
                    "path": path,
                    "file": path,
                    "files": path,
                    "count": "1",
                    "output": String(output.prefix(6_000)),
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }
        // Generic tool.done
        if !toolType.isEmpty {
            let output = (json["output"] as? String) ?? (json["result"] as? String) ?? ""
            return (
                "mcp_tool_call",
                [
                    "title": toolType,
                    "detail": String(output.prefix(200)),
                    "tool": toolType,
                    "output": String(output.prefix(6_000)),
                    "tool_id": callId,
                    "status": "completed",
                ]
            )
        }
        return nil
    }

    // MARK: - Text Extraction

    /// Extract text from Codex JSONL events.
    /// Handles: nested item.content[].text, direct text fields, response.text, etc.
    private static func extractText(from json: [String: Any]) -> String? {
        // Direct text field
        if let text = json["text"] as? String, !text.isEmpty { return text }
        // Nested in item
        if let item = json["item"] as? [String: Any] {
            if let text = item["text"] as? String, !text.isEmpty { return text }
            if let content = item["content"] as? [[String: Any]] {
                let texts = content.compactMap { block -> String? in
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                    return nil
                }
                let joined = texts.joined()
                if !joined.isEmpty { return joined }
            }
            // Recurse into item
            if let nested = extractText(from: item) { return nested }
        }
        // Nested in event
        if let event = json["event"] as? [String: Any] {
            if let nested = extractText(from: event) { return nested }
        }
        // content as array of dicts at top level
        if let content = json["content"] as? [[String: Any]] {
            let texts = content.compactMap { ($0["text"] as? String) }
            let joined = texts.joined()
            if !joined.isEmpty { return joined }
        }
        // response field (some formats)
        if let response = json["response"] as? String, !response.isEmpty { return response }
        return nil
    }

    /// Extract a direct text delta from events like message.output_text.delta
    private static func extractDirectDelta(from json: [String: Any], eventType: String) -> String? {
        // message.output_text.delta → {"type":"message.output_text.delta","delta":"..."}
        if eventType == "message.output_text.delta" || eventType == "response.text.delta" {
            if let delta = json["delta"] as? String, !delta.isEmpty { return delta }
        }
        // response.output_text.delta (variant)
        if eventType == "response.output_text.delta" {
            if let delta = json["delta"] as? String, !delta.isEmpty { return delta }
        }
        return nil
    }

    /// Extract error message from various error event formats
    private static func extractErrorMessage(from json: [String: Any]) -> String? {
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty { return message }
        }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    // MARK: - Legacy Raw Event Parser (backward compat)

    /// Parses Codex JSONL for directly typed events (file_change, command_execution, etc.)
    /// This handles the case where Codex or the app itself emits events with explicit known types.
    private static func parseLegacyRawEvent(from json: [String: Any]) -> (
        type: String, payload: [String: String]
    )? {
        let item = (json["item"] as? [String: Any]) ?? json
        guard let type = (item["type"] as? String) ?? (json["type"] as? String) else { return nil }
        let activityTypes: Set<String> = [
            "file_change", "command_execution", "mcp_tool_call", "web_search",
            "instant_grep", "todo_write", "todo_read", "plan_step_update",
            "read_batch_started", "read_batch_completed",
            "web_search_started", "web_search_completed", "web_search_failed",
        ]
        guard activityTypes.contains(type) else { return nil }

        var payload: [String: String] = [
            "title": titleForType(type, item: item),
            "detail": detailForType(type, item: item),
        ]
        if let path = firstString(in: item, keys: ["path", "file_path", "file", "target_path"]) {
            payload["path"] = path
        }
        if let path = item["path"] as? String { payload["file"] = path }
        if let cmd = firstString(in: item, keys: ["command", "command_line", "cmd"]) {
            payload["command"] = cmd
        }
        if let cwd = firstString(in: item, keys: ["cwd", "working_directory", "workdir"]) {
            payload["cwd"] = cwd
        }
        if let output = firstString(
            in: item, keys: ["output", "result", "stdout", "message", "content"])
        {
            payload["output"] = String(output.prefix(6_000))
        }
        if let stderr = firstString(in: item, keys: ["stderr", "error", "error_message"]),
            !stderr.isEmpty
        {
            payload["stderr"] = String(stderr.prefix(3_000))
        }
        if let tool = firstString(in: item, keys: ["tool", "name"]) { payload["tool"] = tool }
        if let added = item["additions"] as? Int { payload["linesAdded"] = "\(added)" }
        if let added = item["lines_added"] as? Int { payload["linesAdded"] = "\(added)" }
        if let removed = item["deletions"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let removed = item["lines_removed"] as? Int { payload["linesRemoved"] = "\(removed)" }
        if let query = firstString(in: item, keys: ["query", "search_query"]) {
            payload["query"] = query
        }
        if let qid = firstString(in: item, keys: ["query_id", "id"]) { payload["queryId"] = qid }
        if let status = firstString(in: item, keys: ["status"]) { payload["status"] = status }
        if let count = item["result_count"] as? Int { payload["resultCount"] = "\(count)" }
        if let duration = item["duration_ms"] as? Int { payload["duration_ms"] = "\(duration)" }
        if let edits = item["edit_count"] as? Int { payload["editCount"] = "\(edits)" }

        return (type, payload)
    }

    // MARK: - Context Compaction Detection

    private static func containsCompactionSignal(json: [String: Any]) -> Bool {
        if let item = json["item"] as? [String: Any],
            let itemType = item["type"] as? String,
            itemType.lowercased().contains("compaction")
        {
            return true
        }
        if let type = json["type"] as? String, type.lowercased().contains("compaction") {
            return true
        }
        let payload = String(describing: json).lowercased()
        return payload.contains("compaction")
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
            result[unescapeMarker(pair[0]).trimmingCharacters(in: .whitespaces)] =
                unescapeMarker(pair[1]).trimmingCharacters(in: .whitespaces)
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
            return (item["path"] as? String) ?? (item["file_path"] as? String) ?? ""
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

    private static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key], let stringValue = stringify(value), !stringValue.isEmpty {
                return stringValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstString(in: nested, keys: keys)
            {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any],
                        let found = firstString(in: nested, keys: keys)
                    {
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

    /// Parse a JSON string into a [String: String] dictionary (for function call arguments)
    private static func parseJsonArgs(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let data = trimmed.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String {
                out[k] = s
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }
}
