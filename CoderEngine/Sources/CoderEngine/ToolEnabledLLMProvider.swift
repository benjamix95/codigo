import Foundation

// #region agent log
private func _dbgLog(_ msg: String, _ data: [String: Any] = [:]) {
    guard let path = ProcessInfo.processInfo.environment["CODERENGINE_DEBUG_LOG_PATH"],
          !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }
    var payload: [String: Any] = [
        "sessionId": "63fcab",
        "location": "ToolEnabledLLMProvider",
        "message": msg,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    data.forEach { payload[$0.key] = $0.value }
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: json, encoding: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    if let fh = try? FileHandle(forUpdating: URL(fileURLWithPath: path)) {
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        fh.write((line + "\n").data(using: .utf8) ?? Data())
    }
}
// #endregion

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
        \(toolProtocolPrompt)

        \(prompt)
        """

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentPrompt = initialPrompt
                    var conversationTranscript = ""
                    var emittedMarkerIds = Set<String>()
                    var isFirstRound = true

                    for _ in 0..<maxToolRounds {
                        let stream = try await base.send(prompt: currentPrompt, context: context, imageURLs: isFirstRound ? imageURLs : nil)
                        var roundText = ""
                        var roundToolResults: [[String: String]] = []

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                roundText += delta
                                continuation.yield(.textDelta(delta))
                                let markers = CoderIDEMarkerParser.parse(from: roundText)
                                for marker in markers {
                                    let dedupeId = marker.payload["id"] ?? "\(marker.kind)|\(marker.payload.description)"
                                    if emittedMarkerIds.contains(dedupeId) { continue }
                                    emittedMarkerIds.insert(dedupeId)
                                    _dbgLog("marker_parsed", ["hypothesisId": "H1", "kind": marker.kind, "payloadKeys": Array(marker.payload.keys).joined(separator: ","), "runId": "post-fix"])

                                    let produced = await events(for: marker, context: context)
                                    _dbgLog("events_returned", ["hypothesisId": "H1", "kind": marker.kind, "producedCount": produced.count, "runId": "post-fix"])
                                    for e in produced {
                                        continuation.yield(e)
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
                                    let name = payload["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    if name.isEmpty { continue }
                                    var args: [String: String] = [:]
                                    if let argsJson = payload["args"], let parsed = parseArgsJSON(argsJson) {
                                        args = parsed
                                    }
                                    args["id"] = payload["id"] ?? UUID().uuidString
                                    args["name"] = name
                                    let marker = CoderIDEMarker(kind: "tool_call", payload: args)
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
                        let shouldContinue = !roundToolResults.isEmpty
                        _dbgLog("round_end", ["hypothesisId": "H2", "roundToolResultsCount": roundToolResults.count, "willBreak": !shouldContinue, "runId": "post-fix"])
                        guard shouldContinue else { break }
                        currentPrompt = buildFollowUpPrompt(
                            originalPrompt: prompt,
                            transcript: conversationTranscript,
                            toolResults: roundToolResults
                        )
                        isFirstRound = false
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
                if let output = payload["output"], !output.isEmpty {
                    summary["output"] = String(output.prefix(3000))
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
                let output = result["output"].map { "\noutput:\n\($0)" } ?? ""
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
            let toolName = marker.payload["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !toolName.isEmpty else {
                return [.raw(type: "tool_validation_error", payload: [
                    "title": "Tool call invalida",
                    "detail": "Campo name mancante in marker tool_call",
                    "status": "failed"
                ])]
            }
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
            _dbgLog("events_default", ["hypothesisId": "H1", "kind": marker.kind, "unhandled": true, "runId": "post-fix"])
            return []
        }
    }

    private var toolProtocolPrompt: String {
        """
        Se devi usare strumenti, emetti marker strutturati CoderIDE.
        Quando concludi un task, OBBLIGATORIO fornisci un riepilogo finale all'utente: cosa hai fatto, file/comandi usati, esito. Mai concludere senza questo riepilogo.
        Formato:
        [CODERIDE:tool_call|id=<uuid>|name=<read|glob|grep|edit|write|bash|mcp|web_search>|path=...|query=...|command=...|content=...|swarm_id=...]
        Marker supportati anche:
        [CODERIDE:todo_write|title=...|status=pending|priority=medium|notes=...|files=a.swift,b.swift]
        [CODERIDE:todo_read]
        [CODERIDE:instant_grep|query=...|pathScope=...|matchesCount=...|previewLines=...]
        [CODERIDE:plan_step|step_id=...|status=running]
        [CODERIDE:read_batch|count=...|files=...|group_id=...]
        [CODERIDE:web_search|queryId=...|query=...|status=started|group_id=...]
        """
    }
}
