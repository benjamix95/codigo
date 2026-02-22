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
        maxToolRounds: Int = 20
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
                    summary["output"] = String(output.prefix(1200))
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
            (Nessun tool usato nel round precedente.)

            Continua il task. Se servono altri tool emetti [CODERIDE:read|...], [CODERIDE:glob|...], [CODERIDE:grep|...], [CODERIDE:tool_call|...].
            Se hai finito: OBBLIGATORIO fornire un riepilogo finale all'utente: cosa hai fatto, quali file/comandi hai usato, esito. Non concludere mai senza questo riepilogo.
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
            Risultati tool appena eseguiti:
            \(formatted)

            Continua usando questi risultati. Se servono altri tool emetti nuovi marker [CODERIDE:tool_call|...].
            Quando hai finito: OBBLIGATORIO fornire un riepilogo finale all'utente (cosa fatto, file usati, esito). Non concludere senza riepilogo.
            """
        }

        return """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        Prompt utente iniziale:
        \(originalPrompt)

        Transcript parziale:
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
    }

    private func sanitizeVisibleDelta(_ delta: String) -> String {
        if delta.isEmpty { return "" }
        let blockedSnippets = [
            "Prompt utente iniziale:",
            "Transcript parziale:",
            "Risultati tool appena eseguiti:",
            "Quando hai finito: OBBLIGATORIO",
            "(Nessun tool usato nel round precedente.)",
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

        Riepilogo finale automatico:
        Ho completato i tool richiesti e questi sono gli esiti principali:
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
        Hai già eseguito i tool necessari. Ora DEVI produrre SOLO l'esito finale per l'utente.
        Regole obbligatorie:
        1) Non emettere altri marker tool.
        2) Non fermarti finché non scrivi un riepilogo finale completo.
        3) Se manca qualche dato, dichiara cosa manca e proponi il prossimo passo concreto.

        Prompt utente iniziale:
        \(originalPrompt)

        Transcript:
        \(transcript)

        Risultati tool:
        \(compactResults)
        """
    }

    private func isMeaningfulAssistantCompletion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 24 { return false }
        let lower = trimmed.lowercased()
        let blocked = [
            "risultati tool appena eseguiti",
            "prompt utente iniziale",
            "transcript parziale",
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
        Se devi usare strumenti, emetti marker strutturati CoderIDE.
        Non fermarti finché il task non è risolto o finché non hai dichiarato chiaramente un blocco con prossimo passo.
        Quando concludi un task, OBBLIGATORIO fornisci un riepilogo finale all'utente: cosa hai fatto, file/comandi usati, esito. Mai concludere senza questo riepilogo.
        Formato:
        [CODERIDE:tool_call|id=<uuid>|name=<read|glob|grep|edit|write|bash|mcp|web_search|read_range|list_dir|git_diff|search_symbols|run_tests|build_project|list_processes|read_json|write_json|workspace_stats|dependency_audit|tail_log|mcp_list_tools|mcp_call|mcp_describe_tool|mcp_health|mcp_list_servers|mcp_reconnect>|path=...|query=...|command=...|content=...|swarm_id=...]
        Marker supportati anche:
        - Quando costruisci un piano operativo multi-step, emetti SEMPRE anche marker plan step:
          [CODERIDE:plan_step|step_id=1|status=running|title=Analisi]
          [CODERIDE:plan_step|step_id=1|status=done|title=Analisi]
        [CODERIDE:todo_write|title=...|status=pending|priority=medium|notes=...|files=a.swift,b.swift]
        [CODERIDE:todo_read]
        [CODERIDE:instant_grep|query=...|pathScope=...|matchesCount=...|previewLines=...]
        [CODERIDE:plan_step|step_id=...|status=running]
        [CODERIDE:read_batch|count=...|files=...|group_id=...]
        [CODERIDE:web_search|queryId=...|query=...|status=started|group_id=...]
        """
    }
}
