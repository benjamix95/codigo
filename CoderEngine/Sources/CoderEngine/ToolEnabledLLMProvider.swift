import Foundation

public final class ToolEnabledLLMProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let base: any LLMProvider
    private let runtime: UnifiedToolRuntime
    private let policy: ToolRuntimePolicy
    private let executionScope: ExecutionScope
    private let maxToolRounds: Int

    public init(
        base: any LLMProvider,
        runtime: UnifiedToolRuntime? = nil,
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        maxToolRounds: Int = 40
    ) {
        self.base = base
        self.id = base.id
        self.displayName = base.displayName
        self.runtime = runtime ?? UnifiedToolRuntime(executionController: executionController, executionScope: executionScope)
        self.policy = policy
        self.executionScope = executionScope
        self.maxToolRounds = max(1, maxToolRounds)
    }

    public func isAuthenticated() -> Bool {
        base.isAuthenticated()
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let initialPrompt = """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        \(prompt)
        """

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentPrompt = initialPrompt
                    var conversationTranscript = ""
                    var isFirstRound = true
                    var extraContinuationRounds = 0
                    var lastToolResultsForFallback: [[String: String]] = []
                    var emittedVisibleTextAfterToolRound = false
                    var hasAnyMeaningfulAssistantText = false

                    for _ in 0..<maxToolRounds {
                        let stream = try await base.send(prompt: currentPrompt, context: context, imageURLs: isFirstRound ? imageURLs : nil)
                        var roundText = ""
                        var roundToolResults: [[String: String]] = []
                        // Dedupe solo per round corrente: i round successivi possono
                        // legittimamente riemettere lo stesso tool/id.
                        var emittedMarkerIds = Set<String>()
                        var toolCallCountByKey: [String: Int] = [:]
                        var toolCallsThisRound = 0
                        var sawExecutableSuggestion = false
                        var markerCarry = ""

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                roundText += delta
                                let visibleDelta = sanitizeVisibleDelta(delta)
                                if !visibleDelta.isEmpty {
                                    continuation.yield(.textDelta(visibleDelta))
                                    if isMeaningfulAssistantCompletion(visibleDelta) {
                                        emittedVisibleTextAfterToolRound = true
                                        hasAnyMeaningfulAssistantText = true
                                    }
                                }
                                let markers = CoderIDEMarkerParser.parseStreamingChunk(
                                    delta,
                                    carry: &markerCarry
                                )
                                for marker in markers {
                                    let dedupeId = markerDedupeKey(marker)
                                    if emittedMarkerIds.contains(dedupeId) { continue }
                                    if toolCallsThisRound >= policy.maxToolCallsPerRound {
                                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                                            "title": "Budget tool superato",
                                            "detail": "Raggiunto limite tool per round (\(policy.maxToolCallsPerRound))",
                                            "status": "failed",
                                            "error_code": "budget_exceeded"
                                        ]))
                                        continue
                                    }
                                    let count = toolCallCountByKey[dedupeId, default: 0]
                                    if count >= policy.maxRepeatedSameToolPerRound { continue }
                                    toolCallCountByKey[dedupeId] = count + 1
                                    emittedMarkerIds.insert(dedupeId)
                                    toolCallsThisRound += 1

                                    let produced = await events(for: marker, context: context)
                                    for e in produced {
                                        continuation.yield(e)
                                    }
                                    if marker.kind == "tool_call" || marker.kind == "glob" || marker.kind == "read" || marker.kind == "grep" {
                                        sawExecutableSuggestion = true
                                    }
                                    if marker.kind == "tool_call" || ["glob", "read", "grep"].contains(marker.kind),
                                       let summary = summarizeToolResultEvents(produced, marker: marker) {
                                        roundToolResults.append(summary)
                                    } else if marker.kind == "read_batch",
                                       let summary = summarizeReadBatchEvents(produced, marker: marker) {
                                        roundToolResults.append(summary)
                                    }
                                }
                            case .started:
                                if isFirstRound {
                                    continuation.yield(.started)
                                }
                            case .completed:
                                break
                            case .raw(let type, let payload):
                                if type == "tool_call_suggested" {
                                    let isPartial = (payload["is_partial"] ?? "").lowercased() == "true"
                                    if isPartial { continue }
                                    let name = inferredToolName(from: payload)
                                    if name.isEmpty { continue }
                                    if toolCallsThisRound >= policy.maxToolCallsPerRound {
                                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                                            "title": "Budget tool superato",
                                            "detail": "Raggiunto limite tool per round (\(policy.maxToolCallsPerRound))",
                                            "status": "failed",
                                            "error_code": "budget_exceeded"
                                        ]))
                                        continue
                                    }
                                    var args: [String: String] = [:]
                                    if let argsJson = payload["args"], let parsed = parseArgsJSON(argsJson) {
                                        args = parsed
                                    }
                                    args["id"] = payload["id"] ?? UUID().uuidString
                                    args["name"] = name
                                    let marker = CoderIDEMarker(kind: "tool_call", payload: args)
                                    let dedupeId = markerDedupeKey(marker)
                                    let count = toolCallCountByKey[dedupeId, default: 0]
                                    if count >= policy.maxRepeatedSameToolPerRound { continue }
                                    toolCallCountByKey[dedupeId] = count + 1
                                    emittedMarkerIds.insert(dedupeId)
                                    toolCallsThisRound += 1
                                    sawExecutableSuggestion = true
                                    let produced = await events(for: marker, context: context)
                                    for e in produced {
                                        continuation.yield(e)
                                    }
                                    if let summary = summarizeToolResultEvents(produced, marker: marker) {
                                        roundToolResults.append(summary)
                                    }
                                } else {
                                    continuation.yield(event)
                                }
                            default:
                                continuation.yield(event)
                            }
                        }

                        conversationTranscript += "\n[assistant]\n\(roundText)\n"
                        if !roundToolResults.isEmpty {
                            lastToolResultsForFallback = roundToolResults
                            emittedVisibleTextAfterToolRound = false
                        }
                        var shouldContinue = !roundToolResults.isEmpty || sawExecutableSuggestion
                        if !shouldContinue, shouldForceSingleContinuation(roundText), extraContinuationRounds < 1 {
                            shouldContinue = true
                            extraContinuationRounds += 1
                        }
                        guard shouldContinue else { break }
                        currentPrompt = buildFollowUpPrompt(
                            originalPrompt: prompt,
                            transcript: conversationTranscript,
                            toolResults: roundToolResults
                        )
                        isFirstRound = false
                    }

                    if !lastToolResultsForFallback.isEmpty && !emittedVisibleTextAfterToolRound {
                        let forcedPrompt = buildForcedFinalizationPrompt(
                            originalPrompt: prompt,
                            transcript: conversationTranscript,
                            toolResults: lastToolResultsForFallback
                        )
                        do {
                            let forcedStream = try await base.send(
                                prompt: forcedPrompt,
                                context: context,
                                imageURLs: nil
                            )
                            var forcedText = ""
                            for try await forcedEvent in forcedStream {
                                switch forcedEvent {
                                case .textDelta(let delta):
                                    let visible = sanitizeVisibleDelta(delta)
                                    if !visible.isEmpty {
                                        continuation.yield(.textDelta(visible))
                                        forcedText += visible
                                    }
                                default:
                                    break
                                }
                            }
                            if !isMeaningfulAssistantCompletion(forcedText) {
                                continuation.yield(.raw(type: "tool_execution_error", payload: [
                                    "title": "Esito finale mancante",
                                    "detail": "Il provider ha concluso senza riepilogo finale dopo esecuzione tool",
                                    "status": "failed",
                                    "error_code": "missing_final_outcome"
                                ]))
                                let fallback = buildToolFallbackSummary(lastToolResultsForFallback)
                                if !fallback.isEmpty {
                                    continuation.yield(.textDelta(fallback))
                                }
                            } else {
                                hasAnyMeaningfulAssistantText = true
                            }
                        } catch {
                            continuation.yield(.raw(type: "tool_execution_error", payload: [
                                "title": "Finalizzazione fallita",
                                "detail": error.localizedDescription,
                                "status": "failed",
                                "error_code": "missing_final_outcome"
                            ]))
                            let fallback = buildToolFallbackSummary(lastToolResultsForFallback)
                            if !fallback.isEmpty {
                                continuation.yield(.textDelta(fallback))
                            }
                        }
                    }
                    if !hasAnyMeaningfulAssistantText && !lastToolResultsForFallback.isEmpty {
                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                            "title": "Output finale assente",
                            "detail": "Nessun contenuto finale significativo prodotto",
                            "status": "failed",
                            "error_code": "missing_final_outcome"
                        ]))
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

    private func executeReadBatch(marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        let filesStr = marker.payload["files"] ?? ""
        let groupId = marker.payload["group_id"] ?? UUID().uuidString
        let workspacePath = context.workspacePath.path
        func resolvePath(_ raw: String) -> String {
            let t = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            if (t as NSString).isAbsolutePath { return t }
            return (workspacePath as NSString).appendingPathComponent(t)
        }
        let filePaths = filesStr
            .components(separatedBy: ",")
            .map { resolvePath($0) }
            .filter { !$0.isEmpty }
        guard !filePaths.isEmpty else {
            return [
                .raw(type: "read_batch_started", payload: marker.payload),
                .raw(type: "read_batch_completed", payload: [
                    "title": "Read batch",
                    "detail": "Nessun file specificato",
                    "status": "failed",
                    "group_id": groupId
                ])
            ]
        }
        var result: [StreamEvent] = [.raw(type: "read_batch_started", payload: marker.payload)]
        var combinedOutput: [String] = []
        let execContext = ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope)
        for path in filePaths {
            let call = ToolCall(
                id: UUID().uuidString,
                name: "read",
                args: ["path": path],
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            let events = await runtime.execute(call, context: execContext)
            for event in events {
                result.append(event)
                if case .raw(let type, let payload) = event,
                   (type == "read_batch_completed" || payload["status"] == "completed"),
                   let out = payload["output"], !out.isEmpty {
                    combinedOutput.append("--- \(path) ---\n\(out)")
                }
            }
        }
        let output = combinedOutput.joined(separator: "\n\n")
        result.append(.raw(type: "read_batch_completed", payload: [
            "title": "Read batch (\(filePaths.count) file)",
            "detail": filePaths.joined(separator: ", "),
            "path": filePaths.first ?? "",
            "files": filePaths.joined(separator: ","),
            "output": String(output.prefix(12_000)),
            "status": "completed",
            "group_id": groupId
        ]))
        return result
    }

    private func summarizeReadBatchEvents(_ events: [StreamEvent], marker: CoderIDEMarker) -> [String: String]? {
        var lastCompleted: [String: String]?
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "read_batch_completed", payload["status"] == "completed" {
                var summary: [String: String] = [
                    "id": marker.payload["group_id"] ?? UUID().uuidString,
                    "name": "read_batch",
                    "status": "completed",
                    "detail": payload["detail"] ?? payload["title"] ?? "ok"
                ]
                if let output = payload["output"], !output.isEmpty {
                    summary["output"] = String(output.prefix(6000))
                }
                if let path = payload["path"] ?? payload["files"], !path.isEmpty {
                    summary["path"] = path
                }
                lastCompleted = summary
            } else if payload["status"] == "failed" {
                return [
                    "id": marker.payload["group_id"] ?? UUID().uuidString,
                    "name": "read_batch",
                    "status": "failed",
                    "detail": payload["detail"] ?? payload["stderr"] ?? "read_batch failed"
                ]
            }
        }
        return lastCompleted
    }

    private func summarizeToolResultEvents(_ events: [StreamEvent], marker: CoderIDEMarker) -> [String: String]? {
        var summary: [String: String] = [
            "id": marker.payload["id"] ?? UUID().uuidString,
            "name": marker.payload["name"] ?? ""
        ]
        var foundCompletion = false
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                summary["status"] = "failed"
                summary["detail"] = payload["detail"] ?? payload["stderr"] ?? "tool failed"
                foundCompletion = true
            } else if payload["status"] == "completed" {
                summary["status"] = "completed"
                summary["detail"] = payload["detail"] ?? payload["title"] ?? "ok"
                let name = (summary["name"] ?? "").lowercased()
                if let output = payload["output"], !output.isEmpty, name != "bash" && name != "command_execution" {
                    summary["output"] = String(output.prefix(8000))
                }
                if let path = payload["path"] ?? payload["file"], !path.isEmpty {
                    summary["path"] = path
                }
                foundCompletion = true
            }
        }
        return foundCompletion ? summary : nil
    }

    private func buildFollowUpPrompt(originalPrompt: String, transcript: String, toolResults: [[String: String]]) -> String {
        let resultsSection: String
        if toolResults.isEmpty {
            resultsSection = """
            (No tools used in the previous round.)

            Continue the task. If you need more tools, emit [CODERIDE:tool_call|...] markers.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome. Never end without this summary.
            """
        } else {
            let formatted = toolResults.map { result in
                let id = result["id"] ?? "-"
                let name = result["name"] ?? "-"
                let status = result["status"] ?? "unknown"
                let detail = result["detail"] ?? ""
                let path = result["path"].map { "\npath: \($0)" } ?? ""
                let nameLower = name.lowercased()
                let output: String
                if nameLower == "bash" || nameLower == "command_execution" {
                    output = ""
                } else {
                    output = result["output"].map { "\noutput:\n\($0)" } ?? ""
                }
                return "- tool_call id=\(id), name=\(name), status=\(status)\n  detail: \(detail)\(path)\(output)"
            }.joined(separator: "\n")
            resultsSection = """
            Tool results from previous round:
            \(formatted)

            Continue using these results. If you need more tools, emit new [CODERIDE:tool_call|...] markers.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome. Never end without a summary.
            """
        }

        return """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        Original user prompt:
        \(originalPrompt)

        Conversation transcript:
        \(transcript)

        \(resultsSection)
        """
    }

    private func parseArgsJSON(_ raw: String) -> [String: String]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
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

    private func markerDedupeKey(_ marker: CoderIDEMarker) -> String {
        if marker.kind != "tool_call", let id = marker.payload["id"], !id.isEmpty {
            return "\(marker.kind)|id=\(id)"
        }
        let stablePayload = marker.payload
            .filter { $0.key.lowercased() != "id" }
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "|")
        return "\(marker.kind)|\(stablePayload)"
    }

    private func events(for marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        switch marker.kind {
        case "todo_read":
            return [.raw(type: "todo_read", payload: [:])]
        case "todo_write":
            return [.raw(type: "todo_write", payload: marker.payload)]
        case "instant_grep":
            return [.raw(type: "instant_grep", payload: marker.payload)]
        case "plan_step":
            return [.raw(type: "plan_step_update", payload: marker.payload)]
        case "read_batch":
            return await executeReadBatch(marker: marker, context: context)
        case "web_search":
            return [.raw(type: "web_search_started", payload: marker.payload)]
        case "glob", "read", "grep":
            var args = marker.payload
            args["name"] = marker.kind
            args["id"] = args["id"] ?? UUID().uuidString
            if marker.kind == "glob", var pat = args["pattern"], !pat.isEmpty {
                if pat.contains("**/") { pat = pat.replacingOccurrences(of: "**/", with: "") }
                args["pattern"] = pat
            }
            let call = ToolCall(
                id: args["id"] ?? UUID().uuidString,
                name: marker.kind,
                args: args,
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            return await runtime.execute(call, context: ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope))
        case "tool_call":
            let toolName = inferredToolName(from: marker.payload)
            guard !toolName.isEmpty else { return [] }
            let call = ToolCall(
                id: marker.payload["id"] ?? UUID().uuidString,
                name: toolName,
                args: marker.payload,
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            return await runtime.execute(call, context: ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope))
        default:
            return []
        }
    }

    private func inferredToolName(from payload: [String: String]) -> String {
        let explicitCandidates = [
            payload["name"],
            payload["tool"],
            payload["tool_name"],
            payload["function"],
            payload["function_name"],
        ]
        for candidate in explicitCandidates {
            let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if [
                "read", "glob", "grep", "edit", "write", "bash", "mcp", "web_search",
                "str_replace", "create_file",
                "read_range", "list_dir", "git_diff", "search_symbols", "run_tests", "build_project",
                "list_processes", "read_json", "write_json", "workspace_stats", "dependency_audit",
                "tail_log", "mcp_call", "mcp_list_tools", "mcp_describe_tool", "mcp_health",
                "mcp_list_servers", "mcp_reconnect"
            ].contains(name) {
                return name
            }
        }

        if let command = payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "bash"
        }
        if let query = payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let scope = (payload["pathScope"] ?? payload["path_scope"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return scope.isEmpty ? "web_search" : "grep"
        }
        if let pattern = payload["pattern"], !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "glob"
        }
        if let content = payload["content"], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "write"
        }
        if let path = payload["path"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "read"
        }
        return ""
    }

    private func shouldForceSingleContinuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return lower.contains("inizierò") || lower.contains("sto esplorando") || lower.contains("analizzo la struttura")
            || lower.contains("let me ") || lower.contains("i'll start") || lower.contains("i will ")
            || lower.contains("exploring the") || lower.contains("analyzing the")
    }

    private func sanitizeVisibleDelta(_ delta: String) -> String {
        if delta.isEmpty { return "" }
        let blockedSnippets = [
            "Prompt utente iniziale:",
            "Original user prompt:",
            "Transcript parziale:",
            "Conversation transcript:",
            "Risultati tool appena eseguiti:",
            "Tool results from previous round:",
            "Quando hai finito: OBBLIGATORIO",
            "When finished: you MUST provide",
            "(Nessun tool usato nel round precedente.)",
            "(No tools used in the previous round.)",
            "[assistant]",
        ]
        for snippet in blockedSnippets where delta.contains(snippet) {
            return ""
        }
        return delta
    }

    private func buildToolFallbackSummary(_ results: [[String: String]]) -> String {
        let lines = results.prefix(8).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            let path = item["path"] ?? ""
            var line = "- \(name): \(status)"
            if !detail.isEmpty { line += " — \(detail)" }
            if !path.isEmpty { line += " (\(path))" }
            return line
        }
        guard !lines.isEmpty else { return "" }
        return """

        **Summary:**
        \(lines.joined(separator: "\n"))

        """
    }

    private func buildForcedFinalizationPrompt(
        originalPrompt: String,
        transcript: String,
        toolResults: [[String: String]]
    ) -> String {
        let compactResults = toolResults.prefix(10).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            return "- \(name): \(status) \(detail)"
        }.joined(separator: "\n")
        return """
        You have already executed the required tools. Now you MUST produce ONLY the final outcome for the user.
        Mandatory rules:
        1) Do NOT emit any more tool markers.
        2) Do NOT stop until you write a complete final summary.
        3) If any data is missing, state what's missing and propose a concrete next step.

        Original user prompt:
        \(originalPrompt)

        Transcript:
        \(transcript)

        Tool results:
        \(compactResults)
        """
    }

    private func isMeaningfulAssistantCompletion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 24 { return false }
        let lower = trimmed.lowercased()
        let blocked = [
            "risultati tool appena eseguiti",
            "tool results from previous round",
            "prompt utente iniziale",
            "original user prompt:",
            "transcript parziale",
            "conversation transcript:",
            "codieride:tool_call",
            "[assistant]",
        ]
        for snippet in blocked where lower.contains(snippet) {
            return false
        }
        return true
    }

    private var toolProtocolPrompt: String {
        """
        # Tool Protocol

        You have access to powerful tools via CoderIDE markers. Emit them inline in your response.

        ## Core Principles
        1. ALWAYS read a file before editing it — understand current content first.
        2. Use `str_replace` for surgical edits (search-and-replace). ONLY use `write` for brand new files or complete rewrites.
        3. Use `grep` to find code before editing. Use `glob` to find files by name pattern.
        4. Use `bash` for git operations, running commands, installing dependencies, builds, tests.
        5. After making changes, verify by reading the result or running build/tests.
        6. For multi-file changes, work file by file with `str_replace`.
        7. When done, provide a clear summary: what changed, which files, outcome.
        8. Do NOT stop until the task is fully resolved or you've clearly stated a blocker with next steps.

        ## Available Tools

        ### File Operations
        - **read** — Read a file with line numbers. Args: `path`.
        - **str_replace** — Replace exact text in a file. Args: `path`, `old_string`, `new_string`.
          The `old_string` MUST match EXACTLY (including whitespace/indentation).
          If it appears multiple times, add more surrounding context lines to make it unique.
          ALWAYS prefer `str_replace` over `write` for editing existing files.
        - **write** — Write entire file content. ONLY for new files or complete rewrites. Args: `path`, `content`.
        - **create_file** — Create a new file (fails if file exists). Args: `path`, `content`.
        - **read_range** — Read specific line range. Args: `path`, `start`, `end`.
        - **list_dir** — List directory contents. Args: `path`.

        ### Search & Navigation
        - **grep** — Search with regex (powered by ripgrep). Args: `query`, `pathScope` (dir), `fileType` (e.g. swift/ts/py), `context_lines` (0-10).
        - **glob** — Find files by name pattern (powered by ripgrep). Args: `pattern` (e.g. `*.swift`, `**/*Test*`), `path` (scope dir).
        - **search_symbols** — Search code symbols (class, struct, func, etc). Args: `query`, `kind`.

        ### Execution
        - **bash** — Run shell command. Args: `command`, `cwd`.
        - **git_diff** — Show git diff. Args: `path`.
        - **run_tests** — Run tests. Args: `target`, `filter`.
        - **build_project** — Build project. Args: `configuration`, `target`.

        ### Data
        - **read_json** — Read and pretty-print JSON. Args: `path`.
        - **write_json** — Merge patch into JSON file. Args: `path`, `patch`.

        ### MCP (Model Context Protocol)
        - **mcp_call** — Call an MCP tool. Args: `server`, `tool`, plus tool-specific args.
        - **mcp_list_tools** — List available MCP tools. Args: `server` (optional).
        - **mcp_describe_tool** — Get MCP tool schema. Args: `server`, `tool`.
        - **mcp_list_servers** — List connected MCP servers.
        - **mcp_health** — Check MCP server health.
        - **mcp_reconnect** — Reconnect to an MCP server. Args: `server`.

        ### Utility
        - **workspace_stats** — Get file/dir counts and size.
        - **dependency_audit** — Audit dependencies. Args: `manager` (swift/npm/pnpm/yarn).
        - **tail_log** — Read last N lines of a file. Args: `path`, `lines`.
        - **list_processes** — List running processes. Args: `filter`.

        ## Marker Format
        ```
        [CODERIDE:tool_call|id=<uuid>|name=<tool_name>|arg1=value1|arg2=value2]
        ```

        ## Examples

        Read a file:
        [CODERIDE:tool_call|id=abc123|name=read|path=Sources/App/main.swift]

        Edit a file (surgical replace):
        [CODERIDE:tool_call|id=def456|name=str_replace|path=Sources/App/main.swift|old_string=let x = 5|new_string=let x = 10]

        Search for code:
        [CODERIDE:tool_call|id=ghi789|name=grep|query=func viewDidLoad|fileType=swift|context_lines=3]

        Find files:
        [CODERIDE:tool_call|id=jkl012|name=glob|pattern=*ViewController.swift]

        Run a command:
        [CODERIDE:tool_call|id=mno345|name=bash|command=swift build]

        Create a new file:
        [CODERIDE:tool_call|id=pqr678|name=create_file|path=Sources/App/NewFile.swift|content=import Foundation]

        ## Additional Markers
        - Plan steps: [CODERIDE:plan_step|step_id=1|status=running|title=Analysis]
        - Todo: [CODERIDE:todo_write|title=...|status=pending|priority=medium]
        - Read batch: [CODERIDE:read_batch|files=a.swift,b.swift|group_id=...]
        - Web search: [CODERIDE:web_search|query=...|status=started]
        """
    }
}
