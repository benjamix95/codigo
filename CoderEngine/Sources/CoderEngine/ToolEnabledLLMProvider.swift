import Foundation

public final class ToolEnabledLLMProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        base.attachmentCapabilities
    }

    private let base: any LLMProvider
    private let runtime: UnifiedToolRuntime
    private let policy: ToolRuntimePolicy
    private let executionScope: ExecutionScope
    private let maxToolRounds: Int
    private let maxAutonomousContinuationRounds = 4

    public init(
        base: any LLMProvider,
        runtime: UnifiedToolRuntime? = nil,
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        maxToolRounds: Int = 160
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

    public func debugToolRuntimeSnapshot() async -> ToolRuntimeDebugSnapshot {
        await runtime.debugSnapshot()
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
                    let requiredPolicyHash = Self.requiredPolicyHash(from: context)
                    var didEmitPolicyAck = false

                    for _ in 0..<maxToolRounds {
                        let stream = try await base.send(prompt: currentPrompt, context: context, imageURLs: isFirstRound ? imageURLs : nil)
                        var roundText = ""
                        var roundToolResults: [[String: String]] = []
                        // Dedupe only for the current round: subsequent rounds can
                        // legitimately re-emit the same tool/id.
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
                                // Validate markers through dedup/budget checks
                                var validatedMarkers: [CoderIDEMarker] = []
                                for marker in markers {
                                    if Self.isPolicyAckMarker(marker, requiredHash: requiredPolicyHash) {
                                        didEmitPolicyAck = true
                                    }
                                    let dedupeId = markerDedupeKey(marker)
                                    if emittedMarkerIds.contains(dedupeId) { continue }
                                    if toolCallsThisRound >= policy.maxToolCallsPerRound {
                                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                                            "title": "Tool budget exceeded",
                                            "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
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
                                    validatedMarkers.append(marker)
                                }

                                // Execute markers with parallel read-only optimization
                                let batchResults = await executeMarkerBatch(validatedMarkers, context: context)
                                for (marker, produced) in batchResults {
                                    if let hash = requiredPolicyHash,
                                       shouldEmitSyntheticPolicyAck(
                                        for: marker,
                                        requiredHash: hash,
                                        didEmitPolicyAck: didEmitPolicyAck
                                       ) {
                                        continuation.yield(.raw(type: "policy_ack", payload: ["hash": hash]))
                                        didEmitPolicyAck = true
                                    }
                                    for e in produced {
                                        if case .raw(let type, let payload) = e,
                                           type == "policy_ack",
                                           Self.matchesRequiredPolicyHash(
                                            payload["hash"] ?? payload["policy_hash"],
                                            requiredHash: requiredPolicyHash
                                           ) {
                                            didEmitPolicyAck = true
                                        }
                                        continuation.yield(e)
                                    }
                                    if marker.kind == "tool_call" || marker.kind == "glob" || marker.kind == "read" || marker.kind == "grep" || marker.kind == "instant_grep" {
                                        sawExecutableSuggestion = true
                                    }
                                    if marker.kind == "tool_call" || ["glob", "read", "grep", "instant_grep"].contains(marker.kind),
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
                                if type == "policy_ack" {
                                    if Self.matchesRequiredPolicyHash(
                                        payload["hash"] ?? payload["policy_hash"],
                                        requiredHash: requiredPolicyHash
                                    ) {
                                        didEmitPolicyAck = true
                                    }
                                    continuation.yield(event)
                                    continue
                                }
                                if type == "tool_call_suggested" {
                                    let isPartial = (payload["is_partial"] ?? "").lowercased() == "true"
                                    if isPartial { continue }
                                    let name = inferredToolName(from: payload)
                                    if name.isEmpty { continue }
                                    if toolCallsThisRound >= policy.maxToolCallsPerRound {
                                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                                            "title": "Tool budget exceeded",
                                            "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                                            "status": "failed",
                                            "error_code": "budget_exceeded"
                                        ]))
                                        continue
                                    }
                                    var args = payload
                                    let metadataKeys: Set<String> = [
                                        "id", "name", "tool", "tool_name", "function", "function_name",
                                        "args", "is_partial", "type", "status", "title", "detail", "output",
                                    ]
                                    for key in metadataKeys {
                                        args.removeValue(forKey: key)
                                    }
                                    if let argsJson = payload["args"], let parsed = parseArgsJSON(argsJson) {
                                        for (key, value) in parsed {
                                            args[key] = value
                                        }
                                    }
                                    args["id"] = payload["id"] ?? args["id"] ?? UUID().uuidString
                                    args["name"] = name
                                    let marker = CoderIDEMarker(kind: "tool_call", payload: args)
                                    let dedupeId = markerDedupeKey(marker)
                                    let count = toolCallCountByKey[dedupeId, default: 0]
                                    if count >= policy.maxRepeatedSameToolPerRound { continue }
                                    toolCallCountByKey[dedupeId] = count + 1
                                    emittedMarkerIds.insert(dedupeId)
                                    toolCallsThisRound += 1
                                    sawExecutableSuggestion = true
                                    if let hash = requiredPolicyHash,
                                       shouldEmitSyntheticPolicyAck(
                                        for: marker,
                                        requiredHash: hash,
                                        didEmitPolicyAck: didEmitPolicyAck
                                       ) {
                                        continuation.yield(.raw(type: "policy_ack", payload: ["hash": hash]))
                                        didEmitPolicyAck = true
                                    }
                                    let produced = await events(for: marker, context: context)
                                    for e in produced {
                                        if case .raw(let innerType, let innerPayload) = e,
                                           innerType == "policy_ack",
                                           Self.matchesRequiredPolicyHash(
                                            innerPayload["hash"] ?? innerPayload["policy_hash"],
                                            requiredHash: requiredPolicyHash
                                           ) {
                                            didEmitPolicyAck = true
                                        }
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
                        if !shouldContinue,
                           shouldForceAutonomousContinuation(
                            roundText,
                            roundIndex: extraContinuationRounds
                           ),
                           extraContinuationRounds < maxAutonomousContinuationRounds {
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
                                    "title": "Missing final outcome",
                                    "detail": "Provider finished without final summary after tool execution",
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
                                "title": "Finalization failed",
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
                            "title": "Missing final output",
                            "detail": "No meaningful final content produced",
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
                    "detail": "No files specified",
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

    private func summarizeInstantGrepResult(
        events: [StreamEvent],
        markerPayload: [String: String],
        query: String,
        fallbackScope: String
    ) -> [String: String] {
        var payload = markerPayload
        var output = ""
        var durationMs: String?
        var pathScope = fallbackScope
        var matchesCount: Int?
        var previewLines = markerPayload["previewLines"] ?? ""

        for event in events {
            guard case .raw(_, let eventPayload) = event else { continue }
            if let status = eventPayload["status"], status == "completed" {
                if let out = eventPayload["output"], !out.isEmpty {
                    output = out
                }
                if let duration = eventPayload["duration_ms"], !duration.isEmpty {
                    durationMs = duration
                }
                if let scope = eventPayload["pathScope"] ?? eventPayload["path"], !scope.isEmpty {
                    pathScope = scope
                }
                if let countRaw = eventPayload["count"], let parsed = Int(countRaw) {
                    matchesCount = parsed
                }
                if let preview = eventPayload["previewLines"], !preview.isEmpty {
                    previewLines = preview
                }
            }
        }

        let parsedPreview = grepPreviewLines(from: output, limit: 8)
        let parsedLines = previewLines.isEmpty ? parsedPreview.joined(separator: "\n") : previewLines
        let parsedCount = grepPreviewLines(from: output, limit: 10_000).count
        payload["query"] = query
        payload["pathScope"] = pathScope
        payload["scope"] = pathScope
        payload["matchesCount"] = "\(matchesCount ?? parsedCount)"
        payload["previewLines"] = parsedLines
        payload["duration_ms"] = durationMs ?? markerPayload["duration_ms"] ?? ""
        return payload
    }

    private func grepPreviewLines(from output: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var lines: [String] = []
        var seen = Set<String>()

        for rawLine in output.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = rawLine.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count >= 3, let lineNumber = Int(parts[1]) else { continue }
            let preview = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = "\(parts[0]):\(lineNumber):\(preview)"
            guard seen.insert(normalized).inserted else { continue }
            lines.append(normalized)
            if lines.count >= limit { break }
        }
        return lines
    }

    private func buildFollowUpPrompt(originalPrompt: String, transcript: String, toolResults: [[String: String]]) -> String {
        let resultsSection: String
        if toolResults.isEmpty {
            resultsSection = """
            (No tools used in the previous round.)

            Continue the task autonomously until completion.
            If you need more tools, emit [CODERIDE:tool_call|...] markers and execute/verify/fix loops as needed.
            Do not stop at a plan or intention statement.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
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

            Continue using these results autonomously.
            If you need more tools, emit new [CODERIDE:tool_call|...] markers and keep iterating until done.
            If a check fails, fix and re-check before finalizing.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
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

    private func shouldEmitSyntheticPolicyAck(
        for marker: CoderIDEMarker,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck else { return false }
        guard markerRequiresPolicyAck(marker) else { return false }
        return !requiredHash.isEmpty
    }

    private func markerRequiresPolicyAck(_ marker: CoderIDEMarker) -> Bool {
        switch marker.kind {
        case "policy_ack", "todo_read", "todo_write", "plan_step", "debug_panel":
            return false
        default:
            return true
        }
    }

    private static func requiredPolicyHash(from context: WorkspaceContext) -> String? {
        let prompt = context.contextPrompt()
        guard !prompt.isEmpty else { return nil }
        for marker in CoderIDEMarkerParser.parse(from: prompt).reversed() where marker.kind == "policy_ack" {
            let rawHash = marker.payload["hash"] ?? marker.payload["policy_hash"] ?? ""
            let hash = rawHash.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hash.isEmpty {
                return hash
            }
        }
        return nil
    }

    private static func isPolicyAckMarker(
        _ marker: CoderIDEMarker,
        requiredHash: String?
    ) -> Bool {
        guard marker.kind == "policy_ack" else { return false }
        let received = marker.payload["hash"] ?? marker.payload["policy_hash"]
        return matchesRequiredPolicyHash(received, requiredHash: requiredHash)
    }

    private static func matchesRequiredPolicyHash(
        _ receivedHash: String?,
        requiredHash: String?
    ) -> Bool {
        guard let requiredHash, !requiredHash.isEmpty else { return true }
        let received = (receivedHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !received.isEmpty && received == requiredHash
    }

    private func events(for marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        switch marker.kind {
        case "todo_read":
            return [.raw(type: "todo_read", payload: [:])]
        case "todo_write":
            return [.raw(type: "todo_write", payload: marker.payload)]
        case "policy_ack":
            return [.raw(type: "policy_ack", payload: marker.payload)]
        case "instant_grep":
            let query = (marker.payload["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return [.raw(type: "instant_grep", payload: marker.payload)]
            }
            let scope = (marker.payload["pathScope"] ?? marker.payload["scope"] ?? ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var grepArgs: [String: String] = ["query": query]
            grepArgs["pathScope"] = scope.isEmpty ? "." : scope
            if let fileType = marker.payload["fileType"], !fileType.isEmpty {
                grepArgs["fileType"] = fileType
            }
            if let contextLines = marker.payload["context_lines"], !contextLines.isEmpty {
                grepArgs["context_lines"] = contextLines
            }
            if let caseSensitive = marker.payload["case_sensitive"], !caseSensitive.isEmpty {
                grepArgs["case_sensitive"] = caseSensitive
            }
            if let multiline = marker.payload["multiline"], !multiline.isEmpty {
                grepArgs["multiline"] = multiline
            }

            let call = ToolCall(
                id: marker.payload["id"] ?? UUID().uuidString,
                name: "grep",
                args: grepArgs,
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            let searchEvents = await runtime.execute(call, context: ToolExecutionContext(
                workspaceContext: context, policy: policy, executionScope: executionScope))
            let summary = summarizeInstantGrepResult(
                events: searchEvents,
                markerPayload: marker.payload,
                query: query,
                fallbackScope: scope.isEmpty ? "." : scope
            )
            return [.raw(type: "instant_grep", payload: summary)] + searchEvents
        case "plan_step":
            return [.raw(type: "plan_step_update", payload: marker.payload)]
        case "debug_panel":
            return [.raw(type: "debug_panel_update", payload: marker.payload)]
        case "read_batch":
            return await executeReadBatch(marker: marker, context: context)
        case "web_search":
            var args = marker.payload
            args["name"] = "web_search"
            args["id"] = args["id"] ?? UUID().uuidString
            let wsCall = ToolCall(
                id: args["id"] ?? UUID().uuidString,
                name: "web_search",
                args: args,
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            var searchEvents = await runtime.execute(wsCall, context: ToolExecutionContext(
                workspaceContext: context, policy: policy, executionScope: executionScope))
            searchEvents.insert(.raw(type: "web_search_started", payload: marker.payload), at: 0)
            return searchEvents
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
        let supportedTools: Set<String> = [
            "read", "glob", "grep", "edit", "write", "bash", "mcp", "web_search", "web_fetch",
            "str_replace", "create_file",
            "read_range", "list_dir", "git_diff", "search_symbols", "run_tests", "build_project",
            "list_processes", "read_json", "write_json", "workspace_stats", "dependency_audit",
            "tail_log", "mcp_call", "mcp_list_tools", "mcp_describe_tool", "mcp_health",
            "mcp_list_servers", "mcp_reconnect",
            // Codebase index tools
            "codebase_search", "find_symbol", "list_symbols", "find_references",
            "project_structure", "file_outline", "find_files", "codebase_stats",
            "dependency_graph", "list_types", "list_tests", "index_status", "reindex",
            // New Cursor-style tools
            "parallel_apply", "regex_replace", "attempt_completion", "diagnostics",
            // Advanced tools
            "rename_symbol", "find_and_replace_all", "undo_edit", "run_single_test",
            // Debug tools
            "debug_log", "debug_query", "debug_session", "debug_hypothesize",
            "debug_mark", "debug_clean",
            // Cursor-style semantic tools
            "semantic_search", "read_lints", "debug_context"
        ]
        let explicitCandidates = [
            payload["name"],
            payload["tool"],
            payload["tool_name"],
            payload["function"],
            payload["function_name"],
        ]
        for candidate in explicitCandidates {
            let rawName = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawName.isEmpty else { continue }
            let name = ProviderToolEventMapper.normalizeToolIdentifier(rawName)
            if supportedTools.contains(name) {
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

    private func shouldForceAutonomousContinuation(_ text: String, roundIndex: Int) -> Bool {
        if roundIndex >= maxAutonomousContinuationRounds { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isMeaningfulAssistantCompletion(trimmed) {
            return false
        }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let lower = trimmed.lowercased()
        let explicitSignals = [
            "let me ",
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "exploring the",
            "analyzing the",
            "next i'll",
            "next i will",
            "would you like me to",
            "if you want i can",
            "i can continue by"
        ]
        if explicitSignals.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.hasSuffix("...") || lower.hasSuffix(":") {
            return true
        }
        return false
    }

    private func sanitizeVisibleDelta(_ delta: String) -> String {
        if delta.isEmpty { return "" }
        let blockedSnippets = [
            "Initial user prompt:",
            "Original user prompt:",
            "Partial transcript:",
            "Conversation transcript:",
            "Tool results just executed:",
            "Tool results from previous round:",
            "When finished: MANDATORY",
            "When finished: you MUST provide",
            "(No tools used in the previous round.)",
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
            "tool results just executed",
            "tool results from previous round",
            "initial user prompt",
            "original user prompt:",
            "partial transcript",
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
        3. Prefer `semantic_search` for natural language queries ("where is auth handled?", "data saving flow").
        4. Prefer `codebase_search` and `find_symbol` over `grep` when looking for symbol definitions (classes, functions, structs). They use the index and are faster and more precise.
        5. Use `grep` for text/regex search. Use `glob` to find files by name pattern. Use `find_files` for fuzzy file name matching.
        6. Use `file_outline` to understand a file's structure before reading it entirely.
        7. Use `find_references` before refactoring to understand all usages of a symbol.
        8. Use `bash` for git operations, running commands, installing dependencies, builds, tests.
        9. After making changes, verify with `read_lints` (fast, no build) or `diagnostics` (full build). Prefer `read_lints` for quick checks.
        10. Use `parallel_apply` for making multiple independent edits across files in a single call.
        11. If AGENTS.md / SKILL.md / repository runbooks are present in the prompt/context, treat them as mandatory operational policy. Do not skip skill workflows.
        12. If the context contains a mandatory policy acknowledgment marker (`[CODERIDE:policy_ack|hash=...]`), emit it once before any operational tool action.
        13. MCP availability verification is mandatory before MCP usage: `mcp_list_servers` first, then `mcp_list_tools`, then `mcp_describe_tool` (for unfamiliar tools), then `mcp_call`.
        14. When done, provide a clear summary: what changed, which files, outcome, and explicitly list MCP servers/tools used.
        15. Do NOT stop until the task is fully resolved or you've clearly stated a blocker with next steps.

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
        - **semantic_search** — Search code by meaning/intent using BM25 semantic index with AST-aware chunking. Use for questions like "where is authentication handled?", "data saving flow", "error handling logic". Understands synonyms (auth→login, save→persist), camelCase splitting, symbol names, scope context. Args: `query` (natural language), `target_directories` (optional comma-separated dirs), `num_results` (1-50, default 25).
        - **grep** — Regex search (powered by ripgrep). Args: `query`, `pathScope` (dir), `fileType` (e.g. swift/ts/py), `context_lines` (0-10), `case_sensitive` (true/false), `multiline` (true/false).
        - **glob** — Find files by glob pattern. Args: `pattern` (e.g. `*.swift`, `**/*Test*`), `path` (scope dir).
        - **search_symbols** — Search code symbols across all languages. Args: `query`, `kind`.

        ### Codebase Index (index-powered, faster and more precise than grep for symbol search)
        - **codebase_search** — Search symbols by name, kind, or pattern using the structured index. Much faster than grep for finding definitions. Args: `query`, `kind` (class/struct/enum/protocol/function/method/property/test/all), `filePattern` (optional glob).
        - **find_symbol** — Find exact symbol definitions. Args: `query`, `kind` (optional).
        - **list_symbols** — List all symbols in a file (file outline with types, functions, properties). Args: `path`.
        - **find_references** — Find all references to a symbol (definitions + usages). Args: `query`.
        - **project_structure** — Show project file tree. Args: `maxDepth` (default 3).
        - **file_outline** — Structured outline of a file with line numbers. Args: `path`.
        - **find_files** — Fuzzy file finder (faster than glob for name matching). Args: `query`, `extension` (optional).
        - **codebase_stats** — Codebase statistics: files, languages, sizes, symbols.
        - **dependency_graph** — Show imports and dependents of a file. Args: `path`.
        - **list_types** — List all types (class, struct, enum, protocol) in the codebase.
        - **list_tests** — List all tests in the codebase.
        - **index_status** — Show index health and stats.
        - **reindex** — Force re-indexing the workspace.

        ### Advanced Editing
        - **parallel_apply** — Multiple str_replace edits in one call. Args: `edits` (JSON array of objects, each with `path`, `old_string`, `new_string`).
        - **regex_replace** — Regex-based find-and-replace. Args: `path`, `pattern` (regex), `replacement` (supports $1 capture groups), `flags` (optional: i=case-insensitive, m=multiline, s=dotall).
        - **rename_symbol** — Rename a symbol across the entire codebase. Uses the index to find all references, then replaces. Args: `old_name`, `new_name`, `kind` (optional: class/function/etc).
        - **find_and_replace_all** — Workspace-wide find-and-replace across all files. Args: `search` (string or regex), `replacement`, `filePattern` (optional glob like *.swift), `is_regex` (optional: true/false).
        - **undo_edit** — Revert a file to its last committed state (git checkout). Args: `path`.

        ### Execution
        - **bash** — Run shell command. Args: `command`, `cwd`.
        - **git_diff** — Show git diff. Args: `path`.
        - **run_tests** — Run tests. Args: `target`, `filter`.
        - **run_single_test** — Run a single test by name. Auto-detects project type (Swift/Node/Cargo/Go). Args: `test_name`, `file` (optional).
        - **build_project** — Build project. Args: `configuration`, `target`.
        - **diagnostics** — Get build errors/warnings as structured output (runs full build). Args: `manager` (swift/npm/cargo/go, auto-detected if omitted).
        - **read_lints** — Read current linter/diagnostic state WITHOUT running a full build. Much faster than `diagnostics`. Auto-detects project type. Args: `path` (optional: check single file), `severity` (all/error/warning), `limit` (default 50).
        - **attempt_completion** — Signal task completion. Args: `result` (summary), `command` (optional verification command to run).

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

        ### Web Tools
        - **web_search** — Search the web for current information. Returns a JSON array of results, each with `title`, `snippet`, and `url`. Use when you need up-to-date information, current documentation, recent API changes, external references, or anything beyond your training data. Args: `query` (search terms), `explanation` (optional context for the search).
        - **web_fetch** — Fetch a web page and return its content as clean Markdown. Downloads the page HTML and converts it to readable Markdown, stripping scripts, styles, navigation, and non-content elements. Use to read full documentation pages, blog posts, Stack Overflow answers, API references, changelogs, or any URL. Args: `url` (the full URL to fetch). Limits: 128KB download, 12K chars output. Only supports public HTTP(S) pages (no localhost, no auth-protected pages, no binary files).

        **Web tools workflow — always follow this pattern:**
        1. Use `web_search` with a precise query to find relevant URLs and snippets.
        2. Review the search results (titles + snippets) to identify the most promising pages.
        3. Use `web_fetch` on the best 1-3 URLs to read their full content.
        4. Synthesize the information from fetched pages into your response, citing sources.

        **When to use web tools:**
        - Current events, news, recent releases
        - Up-to-date documentation, API references, changelogs
        - Stack Overflow solutions, GitHub issues, blog posts
        - Verifying information that may have changed since training
        - Any time the user asks to "search", "look up", "check online", or provides a URL

        **Best practices:**
        - Write precise search queries (e.g., "Swift URLSession async await timeout" not just "Swift networking")
        - Run multiple searches if covering different aspects
        - Prioritize official sources (docs, repos) over third-party
        - Fetch multiple URLs in parallel when possible (they are read-only tools)
        - Always cite the source URLs in your response
        - If a fetch fails (404, timeout), try an alternative URL from search results

        ### Debug Tools (for debug mode — analyzing bugs, forming hypotheses, tracking investigation)
        - **debug_context** — Gather full debug context in one call: git status, open files, lint errors, recent commits, debug log summary. Use this FIRST when entering debug mode. No required args.
        - **debug_log** — Write an entry to the debug log server. Args: `severity` (error/warning/info/verbose/trace), `source` (file:line or module), `message`, `detail` (optional: stack trace), `category` (optional: compiler/runtime/test/network/custom).
        - **debug_query** — Query the debug log. Args: `severity` (optional filter), `category` (optional), `source` (optional), `search` (text search), `format` (summary/full, default: summary), `limit` (default 100).
        - **debug_session** — Manage debug sessions. Args: `action` (start/end/clear).
        - **debug_hypothesize** — Propose or update a debug hypothesis. Args: `title`, `description`, `status` (proposed/investigating/confirmed/rejected), `evidence` (optional comma-separated list).
        - **debug_mark** — Insert a debug marker (print/log/assert) into a file. The marker is tagged with 🐛 DEBUG for easy cleanup. Args: `path`, `line` (line number), `comment` (description), `code` (optional code to insert).
        - **debug_clean** — Remove ALL debug markers (lines containing 🐛 DEBUG) from a file or entire workspace. Args: `path` (optional, cleans all files if omitted).

        ### Debug Flow (Cursor-style structured debugging)
        When debugging, follow this structured flow:

        **Phase 1: Context Gathering**
        1. Open debug panel: `[CODERIDE:debug_panel|action=open|phase=analyzing]`
        2. Gather full context with `debug_context` (git status, open files, lints, terminal state)
        3. Start a debug session: `debug_session action=start`

        **Phase 2: Error Analysis**
        4. Log observable symptoms: `debug_log severity=error source=... message=...`
        5. Use `read_lints` to check current diagnostic state
        6. If error comes from a tool failure or terminal, log the error message and exit code

        **Phase 3: Context Reconstruction**
        7. Use `semantic_search` to find related code by meaning ("where is the auth handler?")
        8. Use `read`, `grep`, `find_references` to understand implementation
        9. Use `file_outline` and `dependency_graph` to understand structure

        **Phase 4: Hypothesis Formation**
        10. Formulate testable hypotheses: `debug_hypothesize title=... description=... status=proposed`
        11. Ask user questions if needed: `[CODERIDE:debug_panel|action=question|phase=What steps cause the crash?]`

        **Phase 5: Reproduction (optional)**
        12. Ask user to reproduce: `[CODERIDE:debug_panel|action=reproduce]`
        13. Insert debug markers to observe state: `debug_mark path=... line=... comment=... code=...`

        **Phase 6: Investigation & Fix**
        14. Verify one hypothesis at a time with evidence
        15. Update hypothesis status: `debug_hypothesize ... status=confirmed` or `status=rejected`
        16. Apply the fix using `str_replace` / `parallel_apply`

        **Phase 7: Verification**
        17. Verify with `read_lints` (fast) then `diagnostics` or tests
        18. Clean debug markers: `debug_clean`
        19. Mark resolved: `[CODERIDE:debug_panel|action=resolve|phase=description of fix]`

        ### Debug Flow Markers
        - `[CODERIDE:debug_panel|action=open|phase=analyzing]` — Open debug panel and set phase
        - `[CODERIDE:debug_panel|action=reproduce]` — Ask user to reproduce the bug (shows Proceed button)
        - `[CODERIDE:debug_panel|action=question|phase=What steps cause the crash?]` — Ask the user a question
        - `[CODERIDE:debug_panel|action=marker|phase=path/to/file.swift|42|added print for value]` — Track inserted debug marker
        - `[CODERIDE:debug_panel|action=resolve|phase=Fixed the nil crash by adding guard]` — Mark as resolved (shows Fixed button)

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

        Semantic search (BM25 index, natural language):
        [CODERIDE:tool_call|id=sem001|name=semantic_search|query=where is authentication handled]
        [CODERIDE:tool_call|id=sem002|name=semantic_search|query=data saving flow|target_directories=Sources/]
        [CODERIDE:tool_call|id=sem003|name=semantic_search|query=error handling|num_results=10]

        Search for a symbol definition (prefer over grep):
        [CODERIDE:tool_call|id=idx001|name=codebase_search|query=ToolEnabledLLMProvider|kind=class]

        Find all references before refactoring:
        [CODERIDE:tool_call|id=idx002|name=find_references|query=executeRead]

        Get file outline before reading:
        [CODERIDE:tool_call|id=idx003|name=file_outline|path=Sources/App/main.swift]

        Search for code with regex:
        [CODERIDE:tool_call|id=ghi789|name=grep|query=func viewDidLoad|fileType=swift|context_lines=3]

        Find files by name:
        [CODERIDE:tool_call|id=jkl012|name=find_files|query=ViewController]

        Run a command:
        [CODERIDE:tool_call|id=mno345|name=bash|command=swift build]

        Check linter errors (fast, no build):
        [CODERIDE:tool_call|id=lint01|name=read_lints|severity=error]
        [CODERIDE:tool_call|id=lint02|name=read_lints|path=Sources/App/main.swift]

        Multiple edits in one call:
        [CODERIDE:tool_call|id=par001|name=parallel_apply|edits=[{"path":"a.swift","old_string":"foo","new_string":"bar"},{"path":"b.swift","old_string":"baz","new_string":"qux"}]]

        Regex replace:
        [CODERIDE:tool_call|id=reg001|name=regex_replace|path=Sources/App/main.swift|pattern=TODO:\\s*(.+)|replacement=DONE: $1|flags=i]

        Get build diagnostics:
        [CODERIDE:tool_call|id=diag01|name=diagnostics]

        Signal task completion:
        [CODERIDE:tool_call|id=done01|name=attempt_completion|result=Refactored UserService to use async/await|command=swift build]

        Create a new file:
        [CODERIDE:tool_call|id=pqr678|name=create_file|path=Sources/App/NewFile.swift|content=import Foundation]

        Rename a symbol across the codebase:
        [CODERIDE:tool_call|id=ren001|name=rename_symbol|old_name=OldClassName|new_name=NewClassName|kind=class]

        Workspace-wide find and replace:
        [CODERIDE:tool_call|id=far001|name=find_and_replace_all|search=oldFunction|replacement=newFunction|filePattern=*.swift]

        Undo file edits (revert to git):
        [CODERIDE:tool_call|id=undo01|name=undo_edit|path=Sources/App/main.swift]

        Run a single test:
        [CODERIDE:tool_call|id=tst001|name=run_single_test|test_name=testLoginFlow]

        Search the web:
        [CODERIDE:tool_call|id=ws001|name=web_search|query=Swift URLSession async await tutorial 2025]

        Fetch a web page:
        [CODERIDE:tool_call|id=wf001|name=web_fetch|url=https://developer.apple.com/documentation/foundation/urlsession]

        Web search + fetch workflow:
        [CODERIDE:tool_call|id=ws002|name=web_search|query=SwiftUI NavigationStack migration guide]
        (after reviewing results, fetch the best URL)
        [CODERIDE:tool_call|id=wf002|name=web_fetch|url=https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types]

        Gather full debug context:
        [CODERIDE:tool_call|id=dctx01|name=debug_context]

        Start a debug session and log an entry:
        [CODERIDE:tool_call|id=dbg001|name=debug_session|action=start]
        [CODERIDE:tool_call|id=dbg002|name=debug_log|severity=error|source=NetworkManager.swift:42|message=Connection refused|category=runtime]

        Query debug logs:
        [CODERIDE:tool_call|id=dbg003|name=debug_query|severity=error|format=summary]

        Propose a debug hypothesis:
        [CODERIDE:tool_call|id=dbg004|name=debug_hypothesize|title=Timeout caused by DNS resolution|description=The connection timeout occurs because DNS resolution hangs for 30s on IPv6|status=proposed|evidence=error log at line 42,timeout value is 30s]

        Insert a debug marker (print statement):
        [CODERIDE:tool_call|id=dbg005|name=debug_mark|path=Sources/App/NetworkManager.swift|line=42|comment=checking response value|code=print("DEBUG: response = \\(response)")]

        Clean all debug markers from workspace:
        [CODERIDE:tool_call|id=dbg006|name=debug_clean]

        Ask user to reproduce the bug:
        [CODERIDE:debug_panel|action=reproduce]

        Mark bug as resolved:
        [CODERIDE:debug_panel|action=resolve|phase=Fixed nil crash by adding guard statement in NetworkManager.swift:42]

        ## Additional Markers
        - Plan steps: [CODERIDE:plan_step|step_id=1|status=running|title=Analysis]
        - Instant search: [CODERIDE:instant_grep|query=...|id=...]
        - Todo: [CODERIDE:todo_write|title=...|status=pending|priority=medium]
        - Read batch: [CODERIDE:read_batch|files=a.swift,b.swift|group_id=...]
        - Web search: [CODERIDE:web_search|query=...|status=started]
        - Web fetch: [CODERIDE:tool_call|id=...|name=web_fetch|url=https://example.com]
        - Debug panel: [CODERIDE:debug_panel|action=open|phase=analyzing]
        """
    }

    // MARK: - Parallel Tool Execution

    /// Tools that only read data and can safely run concurrently
    private static let readOnlyToolNames: Set<String> = [
        "read", "glob", "grep", "codebase_search", "find_symbol", "list_symbols",
        "find_references", "project_structure", "file_outline", "find_files",
        "codebase_stats", "dependency_graph", "list_types", "list_tests",
        "index_status", "read_range", "list_dir", "git_diff", "read_json",
        "workspace_stats", "tail_log", "list_processes", "search_symbols",
        "mcp_list_tools", "mcp_describe_tool", "mcp_list_servers", "mcp_health",
        "debug_query", "semantic_search", "read_lints", "debug_context",
        "web_search", "web_fetch",
    ]

    private func isReadOnlyMarker(_ marker: CoderIDEMarker) -> Bool {
        switch marker.kind {
        case "glob", "read", "grep":
            return true
        case "tool_call":
            let name = inferredToolName(from: marker.payload).lowercased()
            return Self.readOnlyToolNames.contains(name)
        default:
            return false
        }
    }

    /// Execute a batch of markers, running consecutive read-only tools in parallel
    /// while executing write tools sequentially. Preserves result ordering.
    private func executeMarkerBatch(
        _ markers: [CoderIDEMarker],
        context: WorkspaceContext
    ) async -> [(CoderIDEMarker, [StreamEvent])] {
        guard !markers.isEmpty else { return [] }

        // Single marker — no batching overhead
        if markers.count == 1 {
            let produced = await events(for: markers[0], context: context)
            return [(markers[0], produced)]
        }

        // Group consecutive markers by read-only vs write
        struct MarkerGroup {
            let markers: [CoderIDEMarker]
            let isReadOnly: Bool
        }

        var groups: [MarkerGroup] = []
        var currentBatch: [CoderIDEMarker] = []
        var currentIsReadOnly = isReadOnlyMarker(markers[0])

        for marker in markers {
            let readOnly = isReadOnlyMarker(marker)
            if readOnly == currentIsReadOnly {
                currentBatch.append(marker)
            } else {
                groups.append(MarkerGroup(markers: currentBatch, isReadOnly: currentIsReadOnly))
                currentBatch = [marker]
                currentIsReadOnly = readOnly
            }
        }
        if !currentBatch.isEmpty {
            groups.append(MarkerGroup(markers: currentBatch, isReadOnly: currentIsReadOnly))
        }

        var results: [(CoderIDEMarker, [StreamEvent])] = []

        for group in groups {
            if group.isReadOnly && group.markers.count > 1 {
                // Execute read-only tools in parallel, preserving order
                let batch = group.markers
                let parallelResults = await withTaskGroup(
                    of: (Int, CoderIDEMarker, [StreamEvent]).self
                ) { taskGroup in
                    for (idx, marker) in batch.enumerated() {
                        taskGroup.addTask {
                            let events = await self.events(for: marker, context: context)
                            return (idx, marker, events)
                        }
                    }
                    var collected: [(Int, CoderIDEMarker, [StreamEvent])] = []
                    for await result in taskGroup {
                        collected.append(result)
                    }
                    return collected.sorted { $0.0 < $1.0 }
                }
                for (_, marker, events) in parallelResults {
                    results.append((marker, events))
                }
            } else {
                // Execute sequentially (write tools, or single read-only)
                for marker in group.markers {
                    let produced = await events(for: marker, context: context)
                    results.append((marker, produced))
                }
            }
        }

        return results
    }
}
