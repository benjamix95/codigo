import Foundation

/// Codex sandbox mode: read-only, workspace-write, danger-full-access
public enum CodexSandboxMode: String, CaseIterable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

/// Markers the model can emit to activate the Task Activity Panel
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

/// Provider that uses Codex CLI (`codex exec`)
public final class CodexCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "codex-cli"
    public let displayName = "Codex CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )
    
    private let codexPath: String
    private let sandboxMode: CodexSandboxMode
    private let modelOverride: String?
    private let modelReasoningEffort: String?
    private let modelProviderOverride: String?
    private let preferOpenAIResponsesWireAPI: Bool
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
        modelProviderOverride: String? = nil,
        preferOpenAIResponsesWireAPI: Bool = false,
        yoloMode: Bool = false,
        askForApproval: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = codexPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.codexPath = candidate
        } else {
            self.codexPath = PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        }
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.modelReasoningEffort = modelReasoningEffort?.isEmpty == true ? nil : modelReasoningEffort
        self.modelProviderOverride = modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.preferOpenAIResponsesWireAPI = preferOpenAIResponsesWireAPI
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
        let fullPrompt = SystemPrompts.taskCompletionStrict + "\n\n" + prompt + context.contextPrompt()
        let path = codexPath
        let workspacePath = context.workspacePath
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let execPath = path
                    guard FileManager.default.fileExists(atPath: execPath) else {
                        continuation.yield(.error("Codex CLI not found at \(execPath). Install with: brew install codex"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("codex"))
                        return
                    }
                    
                    let args = Self.buildExecArguments(
                        fullPrompt: fullPrompt,
                        imageURLs: imageURLs,
                        sandboxMode: sandboxMode,
                        yoloMode: yoloMode,
                        askForApproval: askForApproval,
                        workspacePath: workspacePath.path,
                        modelOverride: modelOverride,
                        modelReasoningEffort: modelReasoningEffort,
                        modelProviderOverride: modelProviderOverride,
                        preferOpenAIResponsesWireAPI: preferOpenAIResponsesWireAPI
                    )
                    
                    var env = CodexDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }
                    let invocation = Self.streamInvocation(
                        executable: execPath,
                        arguments: args
                    )
                    let stream = try await ProcessRunner.run(
                        executable: invocation.executable,
                        arguments: invocation.arguments,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    var parserState = CodexStreamParserState()
                    for try await rawLine in stream {
                        let payloads = Self.parseStreamJSONPayloads(from: rawLine)
                        guard !payloads.isEmpty else { continue }
                        for json in payloads {
                            for event in Self.parseStreamJSONEvent(json, state: &parserState) {
                                continuation.yield(event)
                            }
                        }
                    }
                    for event in Self.finalizeStreamJSONState(state: &parserState) {
                        continuation.yield(event)
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func streamInvocation(
        executable: String,
        arguments: [String]
    ) -> (executable: String, arguments: [String]) {
        let scriptPath = "/usr/bin/script"
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            return (executable, arguments)
        }
        // Use PTY to reduce cases of stdout buffered until EOF.
        return (scriptPath, ["-q", "/dev/null", executable] + arguments)
    }

    static func buildExecArguments(
        fullPrompt: String,
        imageURLs: [URL]?,
        sandboxMode: CodexSandboxMode,
        yoloMode: Bool,
        askForApproval: String,
        workspacePath: String,
        modelOverride: String?,
        modelReasoningEffort: String?,
        modelProviderOverride: String?,
        preferOpenAIResponsesWireAPI: Bool
    ) -> [String] {
        var args: [String] = []
        if let urls = imageURLs, !urls.isEmpty {
            let paths = urls.map { $0.path }.joined(separator: ",")
            args += ["exec", "--image", paths]
        } else {
            args += ["exec"]
        }
        args += ["--json"]
        // Codex CLI does not accept --full-auto together with --yolo/--dangerously-bypass-approvals-and-sandbox.
        if !yoloMode {
            args += ["--full-auto"]
        }
        args += [
            "--sandbox", sandboxMode.rawValue,
            "--cd", workspacePath,
            fullPrompt,
        ]

        func insertPromptScopedFlag(_ values: [String]) {
            args.insert(contentsOf: values, at: args.count - 1)
        }
        func insertConfig(_ keyValue: String) {
            insertPromptScopedFlag(["-c", keyValue])
        }

        if yoloMode {
            insertPromptScopedFlag(["--yolo"])
        }
        if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            insertPromptScopedFlag(["--model", model])
        }
        if let effort = modelReasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !effort.isEmpty {
            insertConfig("model_reasoning_effort=\(effort)")
        }
        if let provider = modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty {
            insertConfig("model_provider=\"\(escapedTomlString(provider))\"")
        }
        if shouldInjectOpenAIResponsesWireAPI(
            modelProviderOverride: modelProviderOverride,
            preferOpenAIResponsesWireAPI: preferOpenAIResponsesWireAPI
        ) {
            // Opt-in safety switch: force modern OpenAI wire API for Codex CLI.
            // Useful when older chat-completions wire paths are deprecated upstream.
            insertConfig("model_providers.openai.wire_api=\"responses\"")
        }
        insertConfig("approval_policy=\"\(askForApproval)\"")
        return args
    }

    static func shouldInjectOpenAIResponsesWireAPI(
        modelProviderOverride: String?,
        preferOpenAIResponsesWireAPI: Bool
    ) -> Bool {
        guard preferOpenAIResponsesWireAPI else { return false }
        let provider = modelProviderOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if provider.isEmpty { return true }
        return provider == "openai"
    }

    private static func escapedTomlString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func parseStreamJSONPayloads(from rawLine: String) -> [[String: Any]] {
        let cleaned = cleanedJSONCandidateLine(rawLine)
        guard !cleaned.isEmpty else { return [] }

        if let direct = decodeJSONDictionary(cleaned) {
            return [direct]
        }

        // Fallback: extract any nested JSON objects from noisy/concatenated lines.
        let extracted = extractJSONObjectStrings(from: cleaned)
        if extracted.isEmpty {
            return []
        }
        return extracted.compactMap { decodeJSONDictionary($0) }
    }

    private static func cleanedJSONCandidateLine(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            // Keep tab and printable characters; remove control chars (\0, \b, ^D, etc).
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeJSONDictionary(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func extractJSONObjectStrings(from line: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var startIndex: String.Index?

        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = line.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
                index = line.index(after: index)
                continue
            }

            if ch == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let end = line.index(after: index)
                        results.append(String(line[start..<end]))
                        startIndex = nil
                    }
                }
            }

            index = line.index(after: index)
        }

        return results
    }

    struct CodexStreamParserState {
        struct TurnState {
            var lastObservedAgentText = ""
            var lastValidAgentMessage = ""
            var emittedAnyAssistantDelta = false
        }

        var turn = TurnState()
        var markerCarry = ""
        var scrubCarry = ""
        var emittedRawKeys: Set<String> = []
        var emittedContextCompacted = false

        mutating func resetTurn() {
            turn = TurnState()
            markerCarry = ""
            scrubCarry = ""
        }
    }

    static func parseStreamJSONEvent(
        _ json: [String: Any],
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        var events: [StreamEvent] = []
        let eventType = normalizedEventType((json["type"] as? String) ?? "")

        if eventType == "turn.started" {
            events.append(contentsOf: finalizeAssistantTurnIfNeeded(state: &state))
            state.resetTurn()
            var payload: [String: String] = [
                "title": "Turn started",
                "detail": "Request execution in progress",
                "status": "started",
            ]
            if let turnId = firstString(in: json, keys: ["turn_id", "id"]), !turnId.isEmpty {
                payload["id"] = turnId
                payload["group_id"] = turnId
            }
            appendRawEvent(
                type: "turn_started",
                payload: payload,
                state: &state,
                events: &events
            )
        }

        if eventType == "turn.completed",
           let usage = json["usage"] as? [String: Any],
           let inp = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int),
           let out = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int) {
            appendRawEvent(
                type: "usage",
                payload: [
                    "input_tokens": "\(inp)",
                    "output_tokens": "\(out)",
                    "model": "codex",
                ],
                state: &state,
                events: &events
            )
        }
        if eventType == "turn.completed" {
            var payload: [String: String] = [
                "title": "Turn completed",
                "detail": "Request execution completed",
                "status": "completed",
            ]
            if let turnId = firstString(in: json, keys: ["turn_id", "id"]), !turnId.isEmpty {
                payload["id"] = turnId
                payload["group_id"] = turnId
            }
            appendRawEvent(
                type: "turn_completed",
                payload: payload,
                state: &state,
                events: &events
            )
        }

        if let rawEvent = parseRawEvent(from: json) {
            appendRawEvent(
                type: rawEvent.type,
                payload: rawEvent.payload,
                state: &state,
                events: &events
            )
        }

        if !state.emittedContextCompacted, containsCompactionSignal(json: json) {
            state.emittedContextCompacted = true
            appendRawEvent(
                type: "context_compacted",
                payload: [
                    "title": "Automatically compacting context",
                    "detail": "Codex compacted the context natively.",
                ],
                state: &state,
                events: &events
            )
        }

        if let agentChunk = extractAgentMessageChunk(from: json) {
            events.append(
                contentsOf: processAgentMessageChunk(
                    agentChunk.text,
                    isDelta: agentChunk.isDelta,
                    state: &state
                )
            )
        }

        if eventType == "turn.completed" {
            events.append(contentsOf: finalizeAssistantTurnIfNeeded(state: &state))
            state.resetTurn()
        }

        return events
    }

    static func finalizeStreamJSONState(state: inout CodexStreamParserState) -> [StreamEvent] {
        finalizeAssistantTurnIfNeeded(state: &state)
    }

    private static func processAgentMessageChunk(
        _ text: String,
        isDelta: Bool,
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        guard !text.isEmpty else { return [] }
        var events: [StreamEvent] = []
        var rawDelta = ""

        if isDelta {
            rawDelta = text
            state.turn.lastObservedAgentText += text
            state.turn.lastValidAgentMessage = state.turn.lastObservedAgentText
        } else {
            let previous = state.turn.lastObservedAgentText
            state.turn.lastObservedAgentText = text
            state.turn.lastValidAgentMessage = text
            if text.hasPrefix(previous) {
                rawDelta = String(text.dropFirst(previous.count))
            } else if previous.hasPrefix(text) {
                rawDelta = ""
            } else {
                rawDelta = text
            }
        }

        if !rawDelta.isEmpty {
            emitMarkerEvents(from: rawDelta, state: &state, events: &events)
            let cleaned = scrubTechnicalTextChunk(rawDelta, carry: &state.scrubCarry)
            if !cleaned.isEmpty {
                state.turn.emittedAnyAssistantDelta = true
                events.append(.textDelta(cleaned))
            }
        }

        return events
    }

    private static func finalizeAssistantTurnIfNeeded(
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        guard !state.turn.lastValidAgentMessage.isEmpty else { return [] }
        guard !state.turn.emittedAnyAssistantDelta else { return [] }

        var events: [StreamEvent] = []
        emitMarkerEvents(from: state.turn.lastValidAgentMessage, state: &state, events: &events)
        var cleanupCarry = ""
        let cleaned = scrubTechnicalTextChunk(state.turn.lastValidAgentMessage, carry: &cleanupCarry)
        if !cleaned.isEmpty {
            state.turn.emittedAnyAssistantDelta = true
            events.append(.textDelta(cleaned))
        }
        return events
    }

    private static func emitMarkerEvents(
        from text: String,
        state: inout CodexStreamParserState,
        events: inout [StreamEvent]
    ) {
        for markerEvent in parseInlineControlMarkerEvents(in: text) {
            appendRawEvent(
                type: markerEvent.type,
                payload: markerEvent.payload,
                state: &state,
                events: &events
            )
        }
        for markerEvent in parseCoderIDEMarkerEvents(in: text, carry: &state.markerCarry) {
            appendRawEvent(
                type: markerEvent.type,
                payload: markerEvent.payload,
                state: &state,
                events: &events
            )
        }
    }

    private static func appendRawEvent(
        type: String,
        payload: [String: String],
        state: inout CodexStreamParserState,
        events: inout [StreamEvent]
    ) {
        let key = rawDedupKey(type: type, payload: payload)
        guard state.emittedRawKeys.insert(key).inserted else { return }
        events.append(.raw(type: type, payload: payload))
    }

    static func rawDedupKey(type: String, payload: [String: String]) -> String {
        if type == "reasoning" {
            let group = payload["group_id"] ?? ""
            let preview = String((payload["output"] ?? "").suffix(160))
            return "\(type)|\(group)|\(preview)"
        }
        let identityKeys = [
            "id", "group_id", "queryId", "query_id",
            "tool_call_id", "call_id", "swarm_id", "step_id"
        ]
        let identityKeySet = Set(identityKeys)
        let identifier = identityKeys.compactMap { payload[$0] }.first(where: { !$0.isEmpty }) ?? ""
        let status = (payload["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !identifier.isEmpty || !status.isEmpty {
            let fingerprint = payloadFingerprint(
                payload,
                excluding: identityKeySet.union(["status"])
            )
            if !fingerprint.isEmpty {
                return "\(type)|\(identifier)|\(status)|\(fingerprint)"
            }
            return "\(type)|\(identifier)|\(status)"
        }
        let canonicalPayload = payload.keys.sorted().map { key in
            "\(key)=\(payload[key] ?? "")"
        }.joined(separator: "|")
        return "\(type)|\(canonicalPayload)"
    }

    private static func payloadFingerprint(_ payload: [String: String], excluding ignored: Set<String>) -> String {
        let entries = payload.keys.sorted().compactMap { key -> String? in
            guard !ignored.contains(key) else { return nil }
            let value = String((payload[key] ?? "").prefix(256))
            return "\(key)=\(value)"
        }
        guard !entries.isEmpty else { return "" }
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry)
        }
        return String(hasher.finalize(), radix: 16)
    }

    static func extractAgentMessageChunk(from json: [String: Any]) -> (text: String, isDelta: Bool)? {
        let eventType = (json["type"] as? String) ?? ""

        if eventType.hasPrefix("item."),
           let item = json["item"] as? [String: Any],
           let itemType = item["type"] as? String,
           itemType == "agent_message" {
            if let delta = firstString(in: item, keys: ["delta", "text_delta"]), !delta.isEmpty {
                return (delta, true)
            }
            if let text = extractTextPayload(from: item), !text.isEmpty {
                return (text, false)
            }
            return nil
        }

        if eventType == "agent_message" {
            if let text = extractTextPayload(from: json), !text.isEmpty {
                return (text, false)
            }
        }

        return nil
    }

    static func extractTextPayload(from obj: Any) -> String? {
        if let s = obj as? String {
            return s
        }
        if let dict = obj as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let output = dict["output"] as? String { return output }
            if let message = dict["message"] {
                if let extracted = extractTextPayload(from: message), !extracted.isEmpty {
                    return extracted
                }
            }
            if let item = dict["item"] {
                if let extracted = extractTextPayload(from: item), !extracted.isEmpty {
                    return extracted
                }
            }
            if let event = dict["event"] {
                if let extracted = extractTextPayload(from: event), !extracted.isEmpty {
                    return extracted
                }
            }
            if let content = dict["content"] as? [Any] {
                let chunks = content.compactMap { extractTextPayload(from: $0) }
                if !chunks.isEmpty {
                    return chunks.joined()
                }
            }
            if let output = dict["output"] as? [Any] {
                let chunks = output.compactMap { extractTextPayload(from: $0) }
                if !chunks.isEmpty {
                    return chunks.joined()
                }
            }
            return nil
        }
        if let array = obj as? [Any] {
            let chunks = array.compactMap { extractTextPayload(from: $0) }
            if !chunks.isEmpty {
                return chunks.joined()
            }
        }
        return nil
    }

    private static func parseInlineControlMarkerEvents(
        in text: String
    ) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []
        if text.contains(CoderIDEMarkers.showTaskPanel) {
            events.append((type: "coderide_show_task_panel", payload: [:]))
        }
        if let start = text.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
           let endRange = text[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
            let task = String(text[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !task.isEmpty {
                events.append((type: "coderide_invoke_swarm", payload: ["task": task]))
            }
        }
        return events
    }
    
    /// Parses Codex JSONL for structured events (file_change, command_execution, mcp_tool_call, web_search)
    static func parseRawEvent(from json: [String: Any]) -> (type: String, payload: [String: String])? {
        let eventType = normalizedEventType((json["type"] as? String) ?? "")
        let item = (json["item"] as? [String: Any]) ?? json
        guard let type = (item["type"] as? String) ?? (eventType.hasPrefix("item.") ? nil : eventType) else { return nil }

        if type == "reasoning" {
            let rawOutput =
                firstString(in: item, keys: ["output", "text", "reasoning", "content", "message"])
                ?? extractTextPayload(from: item)
                ?? ""
            let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOutput.isEmpty else { return nil }

            let output = String(rawOutput.prefix(12_000))
            let detail = String(
                output
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(240)
            )
            var payload: [String: String] = [
                "title": firstString(in: item, keys: ["title", "label"]) ?? "Reasoning",
                "output": output,
                "detail": detail
            ]

            let reasoningId =
                firstString(in: item, keys: ["group_id", "id", "reasoning_id"])
                ?? firstString(in: json, keys: ["turn_id", "id"])
                ?? ""
            if !reasoningId.isEmpty {
                payload["group_id"] = reasoningId.hasPrefix("reasoning-")
                    ? reasoningId
                    : "reasoning-\(reasoningId)"
            } else {
                payload["group_id"] = "reasoning-stream"
            }
            return ("reasoning", payload)
        }

        let activityTypes: Set<String> = [
            "file_change",
            "command_execution",
            "mcp_tool_call",
            "web_search",
            "web_fetch",
            "instant_grep",
            "todo_write",
            "todo_read",
            "plan_step_update",
            "read_batch_started",
            "read_batch_completed",
            "web_search_started",
            "web_search_completed",
            "web_search_failed",
            "web_fetch_started",
            "web_fetch_completed",
            "web_fetch_failed",
        ]
        if !activityTypes.contains(type) {
            return mapToolLikeRawEvent(type: type, eventType: eventType, item: item)
        }
        
        var payload: [String: String] = [
            "title": titleForType(type, item: item),
            "detail": detailForType(type, item: item),
        ]
        if let itemId = firstString(in: item, keys: ["id"]) { payload["id"] = itemId }
        if let path = firstString(
            in: item,
            keys: ["path", "file_path", "file", "target_path", "relative_path"]
        ) {
            payload["path"] = path
            payload["file"] = path
        }
        if let path = item["path"] as? String { payload["file"] = path }
        if let cmd = firstString(in: item, keys: ["command", "command_line", "cmd"]) { payload["command"] = cmd }
        if let cwd = firstString(in: item, keys: ["cwd", "working_directory", "workdir"]) { payload["cwd"] = cwd }
        if let output = firstString(in: item, keys: ["output", "result", "stdout", "message", "content", "text"]) {
            payload["output"] = String(output.prefix(6_000))
        }
        if let stderr = firstString(in: item, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
            payload["stderr"] = String(stderr.prefix(3_000))
        }
        if let tool = firstString(in: item, keys: ["tool", "name"]) {
            payload["tool"] = ProviderToolEventMapper.normalizeToolIdentifier(tool)
            payload["tool_raw"] = tool
        }
        if let mcpTool = firstString(in: item, keys: ["mcp_tool", "tool_name"]) { payload["mcp_tool"] = mcpTool }
        if let mcpServer = firstString(in: item, keys: ["mcp_server", "server_id", "server", "server_name"]) {
            payload["mcp_server"] = mcpServer
            payload["server_id"] = payload["server_id"] ?? mcpServer
        }
        if let added = firstInt(
            in: item,
            keys: ["additions", "lines_added", "linesAdded", "insertions"]
        ) {
            payload["linesAdded"] = "\(added)"
        }
        if let removed = firstInt(
            in: item,
            keys: ["deletions", "lines_removed", "linesRemoved", "deletions_count"]
        ) {
            payload["linesRemoved"] = "\(removed)"
        }
        if type == "file_change" {
            if let diffPreview = firstString(
                in: item,
                keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
            ), !diffPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["diffPreview"] = String(diffPreview.prefix(12_000))
            }
            if let changeType = firstString(
                in: item,
                keys: ["change_type", "operation", "action", "edit_type"]
            ), !changeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["change_type"] = changeType
            }
            // Recompute title/detail from enriched payload for consistency.
            payload["title"] = fileChangeTitle(from: payload)
            payload["detail"] = payload["path"] ?? payload["detail"] ?? ""
        }
        if let query = firstString(in: item, keys: ["query", "search_query"]) { payload["query"] = query }
        if let qid = firstString(in: item, keys: ["query_id", "id"]) { payload["queryId"] = qid }
        if let status = firstString(in: item, keys: ["status"]) { payload["status"] = status }
        if payload["status"] == nil {
            switch eventType {
            case "item.started":
                payload["status"] = "started"
            case "item.updated":
                payload["status"] = "in_progress"
            case "item.completed":
                payload["status"] = "completed"
            default:
                break
            }
        }
        if let groupId = firstString(in: item, keys: ["group_id", "id"]) { payload["group_id"] = groupId }
        if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]) { payload["tool_call_id"] = toolCallId }
        if let count = item["result_count"] as? Int { payload["resultCount"] = "\(count)" }
        if let duration = item["duration_ms"] as? Int { payload["duration_ms"] = "\(duration)" }
        if let edits = item["edit_count"] as? Int { payload["editCount"] = "\(edits)" }
        if type == "mcp_tool_call" {
            payload["title"] = mcpEventTitle(from: item)
            let detail = mcpEventDetail(from: item)
            if !detail.isEmpty {
                payload["detail"] = detail
            }
        }
        
        return (type, payload)
    }

    private static func mapToolLikeRawEvent(
        type: String,
        eventType: String,
        item: [String: Any]
    ) -> (type: String, payload: [String: String])? {
        guard isToolLikeRawEvent(type: type, eventType: eventType, item: item) else { return nil }

        let explicitTool = firstString(
            in: item,
            keys: ["tool", "tool_name", "function_name", "function", "name", "mcp_tool"]
        ) ?? ""
        let normalizedType = ProviderToolEventMapper.normalizeToolIdentifier(type)
        let normalizedExplicitTool = ProviderToolEventMapper.normalizeToolIdentifier(explicitTool)
        let genericTypes: Set<String> = ["tool_call", "function_call", "tool_result", "function_result", "call"]

        let rawToolName: String
        if !normalizedExplicitTool.isEmpty {
            rawToolName = explicitTool
        } else if !genericTypes.contains(normalizedType) {
            rawToolName = type
        } else {
            return nil
        }

        guard let mapped = ProviderToolEventMapper.map(
            toolName: rawToolName,
            payload: item,
            typeHint: type
        ) else {
            return nil
        }

        var payload = mapped.payload
        if payload["tool"] == nil || payload["tool"]?.isEmpty == true {
            payload["tool"] = ProviderToolEventMapper.normalizeToolIdentifier(rawToolName)
        }

        if let status = firstString(in: item, keys: ["status"]), !status.isEmpty {
            payload["status"] = status
        } else if payload["status"] == nil {
            switch eventType {
            case "item.started":
                payload["status"] = "started"
            case "item.updated":
                payload["status"] = "in_progress"
            case "item.completed":
                payload["status"] = "completed"
            default:
                break
            }
        }

        if let itemId = firstString(in: item, keys: ["id"]), !itemId.isEmpty {
            payload["id"] = itemId
            if payload["group_id"] == nil || payload["group_id"]?.isEmpty == true {
                payload["group_id"] = itemId
            }
        }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]), !toolCallId.isEmpty {
            payload["tool_call_id"] = toolCallId
        } else if payload["tool_call_id"] == nil,
                  let id = payload["id"], !id.isEmpty {
            payload["tool_call_id"] = id
        }
        if let swarmId = firstString(in: item, keys: ["swarm_id"]), !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            if payload["group_id"] == nil || payload["group_id"]?.isEmpty == true {
                payload["group_id"] = "swarm-\(swarmId)"
            }
        }

        return (mapped.type, payload)
    }

    private static func isToolLikeRawEvent(
        type: String,
        eventType: String,
        item: [String: Any]
    ) -> Bool {
        let normalizedType = ProviderToolEventMapper.normalizeToolIdentifier(type)
        guard !normalizedType.isEmpty else { return false }

        let nonToolTypes: Set<String> = [
            "reasoning",
            "agent_message",
            "assistant_message",
            "user_message",
            "message",
            "text",
            "final_answer",
        ]
        if nonToolTypes.contains(normalizedType) { return false }

        if eventType.contains("tool") || eventType.contains("function_call") {
            return true
        }

        let toolLikeTypes: Set<String> = [
            "tool_call",
            "function_call",
            "tool_result",
            "function_result",
            "command_execution",
            "file_change",
            "mcp_tool_call",
            "skill",
            "skill_invocation",
            "todo_write",
            "todo_read",
            "web_search",
            "web_fetch",
            "instant_grep",
            "search",
            "semantic_search",
            "codebase_search",
            "find_symbol",
            "find_references",
            "file_outline",
            "list_symbols",
            "read",
            "read_range",
            "list_dir",
            "glob",
            "grep",
            "str_replace",
            "edit",
            "write",
            "create_file",
            "delete_file",
            "parallel_apply",
            "rename_symbol",
            "find_files",
            "mcp_call",
            "mcp_list_servers",
            "mcp_list_tools",
            "mcp_describe_tool",
            "mcp_health",
            "mcp_reconnect",
            "index_status",
            "reindex",
            "read_lints",
            "debug_context",
            "diagnostics",
        ]
        if toolLikeTypes.contains(normalizedType) { return true }
        if normalizedType.hasPrefix("mcp_") || normalizedType.hasPrefix("web_") { return true }

        let toolSignalKeys = [
            "tool",
            "tool_name",
            "function",
            "function_name",
            "mcp_tool",
            "mcp_server",
            "server_id",
            "command",
            "command_line",
            "cmd",
            "old_string",
            "new_string",
            "query",
            "pattern",
            "args",
            "arguments",
        ]
        return firstString(in: item, keys: toolSignalKeys) != nil
    }

    private static func normalizedEventType(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
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

    private static func firstInt(in input: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = input[key] else { continue }
            if let intValue = intValue(from: value) {
                return intValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private static func intValue(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
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
        // Defensive fallback: intercept any text-based payloads that include the keyword.
        let payload = String(describing: json).lowercased()
        return payload.contains("compaction")
    }

    static func parseCoderIDEMarkerEvents(in text: String, carry: inout String) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []
        let markers = CoderIDEMarkerParser.parseStreamingChunk(text, carry: &carry)
        for marker in markers {
            switch marker.kind {
            case "todo_read":
                events.append((type: "todo_read", payload: [:]))
            case "todo_write":
                events.append((type: "todo_write", payload: marker.payload))
            case "instant_grep":
                events.append((type: "instant_grep", payload: marker.payload))
            case "plan_step":
                events.append((type: "plan_step_update", payload: marker.payload))
            case "debug_panel":
                events.append((type: "debug_panel_update", payload: marker.payload))
            case "read_batch":
                events.append((type: "read_batch_started", payload: marker.payload))
            case "web_search":
                events.append((type: "web_search_started", payload: marker.payload))
            case "web_fetch":
                events.append((type: "web_fetch_started", payload: marker.payload))
            case "policy_ack":
                events.append((type: "policy_ack", payload: marker.payload))
            default:
                break
            }
        }
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

    private static func scrubTechnicalTextChunk(_ input: String, carry: inout String) -> String {
        var out = carry + input
        carry = ""

        while let start = out.range(of: "[CODERIDE", options: .caseInsensitive) {
            if let end = out[start.lowerBound...].firstIndex(of: "]") {
                out.removeSubrange(start.lowerBound...end)
            } else {
                carry = String(out[start.lowerBound...])
                out.removeSubrange(start.lowerBound..<out.endIndex)
                break
            }
        }

        out = out.replacingOccurrences(
            of: #"(?i)\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|panel_write|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|[^\n\r]*"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^|\n\r\]]+(?:\||\])?"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^Planning\s+(?:bug\s+review|code\s+review)\s+workflow\s*$"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^(\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+)"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^(?:(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+(?:initial\s+)?(?:task\s+panel|todo|workflow|workflow\s+steps?|project\s+analysis|analysis|plan|execution|execution\s+flow|operations?)\b[^\n]*|(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+[^\n]*(?:task\s+panel|todo|workflow|analysis|plan|execution)\b[^\n]*)$"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        // Importante: non fare trim sui chunk streaming.
        // I delta possono essere solo spazio/newline; se li scartiamo sembra che lo stream si blocchi.
        return out
    }
    
    private static func titleForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            var payload: [String: String] = [:]
            if let path = firstString(
                in: item,
                keys: ["path", "file_path", "file", "target_path", "relative_path"]
            ) {
                payload["path"] = path
            }
            if let changeType = firstString(
                in: item,
                keys: ["change_type", "operation", "action", "edit_type", "tool", "name"]
            ) {
                payload["change_type"] = changeType
            }
            return fileChangeTitle(from: payload)
        case "command_execution":
            let cmd = (item["command"] as? String) ?? (item["command_line"] as? String) ?? "command"
            return "Bash • \(String(cmd.prefix(50)))..."
        case "mcp_tool_call":
            return mcpEventTitle(from: item)
        case "web_search":
            return "Search"
        case "web_fetch":
            return "Fetch"
        default:
            return type
        }
    }
    
    private static func detailForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            return firstString(
                in: item,
                keys: ["path", "file_path", "file", "target_path", "relative_path"]
            ) ?? ""
        case "command_execution":
            return (item["command"] as? String) ?? (item["command_line"] as? String) ?? ""
        case "mcp_tool_call":
            return mcpEventDetail(from: item)
        case "web_search":
            return (item["query"] as? String) ?? ""
        case "web_fetch":
            return (item["url"] as? String) ?? ""
        default:
            return ""
        }
    }

    private static func fileChangeTitle(from payload: [String: String]) -> String {
        let path = (payload["path"] ?? payload["file"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let basename = path.isEmpty ? "file" : (path as NSString).lastPathComponent
        let normalized = (payload["change_type"] ?? payload["operation"] ?? payload["action"] ?? payload["edit_type"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let label: String
        if normalized.contains("create")
            || normalized == "a"
            || normalized == "add"
            || normalized == "added"
            || normalized == "create_file"
        {
            label = "Created"
        } else if normalized.contains("delete")
            || normalized.contains("remove")
            || normalized == "d"
            || normalized == "deleted"
        {
            label = "Deleted"
        } else {
            label = "Edited"
        }

        if basename.isEmpty || basename == "file" {
            return "\(label) file"
        }
        return "\(label) \(basename)"
    }

    private static func mcpEventTitle(from item: [String: Any]) -> String {
        let rawTool = firstString(in: item, keys: ["tool", "name"]) ?? ""
        let tool = rawTool.lowercased()
        let server = (firstString(in: item, keys: ["mcp_server", "server_id", "server"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpTool = (firstString(in: item, keys: ["mcp_tool", "tool_name"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch tool {
        case "mcp_list_servers":
            return "MCP discovery • servers"
        case "mcp_list_tools":
            return "MCP discovery • tools"
        case "mcp_describe_tool":
            return "MCP inspect • \(mcpTool.isEmpty ? "tool" : mcpTool)"
        case "mcp_health":
            return "MCP health check"
        case "mcp_reconnect":
            return "MCP reconnect • \(server.isEmpty ? "server" : server)"
        default:
            if !mcpTool.isEmpty || !server.isEmpty || tool.hasPrefix("mcp") {
                var target = !mcpTool.isEmpty ? mcpTool : rawTool
                if target.isEmpty { target = "tool" }
                if !server.isEmpty {
                    return "MCP call • \(server)/\(target)"
                }
                return "MCP call • \(target)"
            }
            return rawTool.isEmpty ? "MCP operation" : rawTool
        }
    }

    private static func mcpEventDetail(from item: [String: Any]) -> String {
        let detail = firstString(in: item, keys: ["detail", "query", "arguments"]) ?? ""
        if !detail.isEmpty {
            return detail
        }
        let output = firstString(in: item, keys: ["output", "result", "message", "content", "text"]) ?? ""
        return String(output.prefix(160))
    }
}
