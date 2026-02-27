import Foundation

/// Lightweight internal representation of a tool call used by the tool execution loop.
/// Previously part of CoderIDEMarkerParser; kept here for the native tool_call_suggested path.
struct CoderIDEMarker {
    let kind: String
    let payload: [String: String]
}

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
                                if let hash = requiredPolicyHash,
                                   shouldEmitSyntheticPolicyAck(
                                    forRawEventType: type,
                                    requiredHash: hash,
                                    didEmitPolicyAck: didEmitPolicyAck
                                   ) {
                                    continuation.yield(.raw(type: "policy_ack", payload: ["hash": hash]))
                                    didEmitPolicyAck = true
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
                                    // Emit a real-time "started" event BEFORE tool execution
                                    // so the tool trace shows live progress (like Codex CLI).
                                    // Todo updates are lightweight state events and should not
                                    // be represented as generic running tool operations.
                                    if name != "todo_write", name != "todo_read" {
                                        let startType = Self.toolStartEventType(for: name)
                                        let startPayload = Self.toolStartPayload(for: name, args: args)
                                        continuation.yield(.raw(type: startType, payload: startPayload))
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

            Continue the task autonomously until completion.
            If you need more tools, use tool calls and execute/verify/fix loops as needed.
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
            If you need more tools, use tool calls and keep iterating until done.
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
        case "policy_ack", "todo_read", "todo_write", "plan_step":
            return false
        case "tool_call":
            let toolName = inferredToolName(from: marker.payload)
            if [
                "todo_read", "todo_write", "plan_step_update", "mermaid_render",
                "debug_set_phase", "debug_request_user", "debug_resolve",
                "policy_ack", "activate_plan_mode", "activate_debug_mode",
                "show_task_panel", "invoke_swarm", "show_swarm_panel",
            ].contains(toolName) {
                return false
            }
            return true
        default:
            return true
        }
    }

    private func shouldEmitSyntheticPolicyAck(
        forRawEventType type: String,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck, !requiredHash.isEmpty else { return false }
        return rawEventRequiresPolicyAck(type)
    }

    private func rawEventRequiresPolicyAck(_ type: String) -> Bool {
        switch type {
        case "policy_ack", "turn_started", "turn_completed", "usage", "reasoning",
            "todo_read", "todo_write", "plan_step_update", "context_compacted",
            "debug_phase_update", "debug_user_request", "debug_resolved",
            "activate_plan_mode", "activate_debug_mode",
            "coderide_show_task_panel", "coderide_invoke_swarm", "coderide_show_swarm_panel",
            "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied":
            return false
        default:
            return true
        }
    }

    private static func requiredPolicyHash(from context: WorkspaceContext) -> String? {
        let prompt = context.contextPrompt()
        guard !prompt.isEmpty else { return nil }
        // Extract the last policy_ack hash from the context prompt.
        // Matches both marker format [CODERIDE:policy_ack|hash=...] and plain hash= patterns.
        let pattern = #"\bpolicy_ack\b[^]]*\bhash=([^\s|\]\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsPrompt = prompt as NSString
        let matches = regex.matches(in: prompt, range: NSRange(location: 0, length: nsPrompt.length))
        // Take the last match (most recent policy hash)
        guard let lastMatch = matches.last, lastMatch.numberOfRanges >= 2 else { return nil }
        let hash = nsPrompt.substring(with: lastMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    private static func matchesRequiredPolicyHash(
        _ receivedHash: String?,
        requiredHash: String?
    ) -> Bool {
        guard let requiredHash, !requiredHash.isEmpty else { return true }
        let received = (receivedHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !received.isEmpty && received == requiredHash
    }

    /// Resolve a tool call (from native tool_call_suggested) into stream events.
    /// IDE-state tools are emitted as raw events; everything else goes through UnifiedToolRuntime.
    private func events(for marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        guard marker.kind == "tool_call" else { return [] }
        let toolName = inferredToolName(from: marker.payload)
        guard !toolName.isEmpty else { return [] }

        if let enforcementEvents = await enforcedMCPEditEventsIfNeeded(
            marker: marker,
            toolName: toolName,
            context: context
        ) {
            return enforcementEvents
        }

        // IDE state tools — pass-through as raw events, not executed through runtime
        switch toolName {
        case "todo_read":
            return [.raw(type: "todo_read", payload: [:])]
        case "todo_write":
            return [.raw(type: "todo_write", payload: marker.payload)]
        case "policy_ack":
            return [.raw(type: "policy_ack", payload: marker.payload)]
        case "plan_step_update":
            return [.raw(type: "plan_step_update", payload: marker.payload)]
        case "debug_panel":
            return [.raw(type: "tool_validation_error", payload: [
                "title": "Legacy debug_panel is not supported",
                "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                "status": "failed",
                "error_code": "legacy_debug_panel_removed",
                "tool": "debug_panel",
            ])]
        case "debug_set_phase":
            return [.raw(type: "debug_phase_update", payload: marker.payload)]
        case "debug_request_user":
            return [.raw(type: "debug_user_request", payload: marker.payload)]
        case "debug_resolve":
            return [.raw(type: "debug_resolved", payload: marker.payload)]
        case "mermaid_render":
            return [.raw(type: "mermaid_render", payload: marker.payload)]
        case "activate_plan_mode":
            return [.raw(type: "activate_plan_mode", payload: marker.payload)]
        case "activate_debug_mode":
            return [.raw(type: "activate_debug_mode", payload: marker.payload)]
        case "show_task_panel":
            return [.raw(type: "coderide_show_task_panel", payload: [:])]
        case "invoke_swarm":
            return [.raw(type: "coderide_invoke_swarm", payload: marker.payload)]
        case "show_swarm_panel":
            return [.raw(type: "coderide_show_swarm_panel", payload: marker.payload)]
        default:
            break
        }

        // All other tools — execute through UnifiedToolRuntime
        let call = ToolCall(
            id: marker.payload["id"] ?? UUID().uuidString,
            name: toolName,
            args: marker.payload,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )
        return await runtime.execute(call, context: ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope))
    }

    private func enforcedMCPEditEventsIfNeeded(
        marker: CoderIDEMarker,
        toolName: String,
        context: WorkspaceContext
    ) async -> [StreamEvent]? {
        guard policy.enforceMCPEditOnly else { return nil }
        guard Self.mcpEditLikeTools.contains(toolName.lowercased()) else { return nil }

        guard policy.enableMCP else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "MCP-only editing is enforced, but MCP is disabled by policy.",
                    reroutedTool: nil
                )
            ]
        }

        guard let reroute = Self.rerouteEditToolToMCP(
            toolName: toolName,
            args: marker.payload
        ) else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Tool '\(toolName)' is not reroutable to coderide MCP editing.",
                    reroutedTool: nil
                )
            ]
        }

        var reroutedArgs = reroute.args
        reroutedArgs["id"] = marker.payload["id"] ?? UUID().uuidString
        reroutedArgs["name"] = "mcp_call"
        reroutedArgs["tool"] = reroute.mcpTool
        reroutedArgs["server"] = "coderide"
        reroutedArgs["mcp_server"] = "coderide"
        reroutedArgs["mcp_tool"] = reroute.mcpTool

        let reroutedCall = ToolCall(
            id: reroutedArgs["id"] ?? UUID().uuidString,
            name: "mcp_call",
            args: reroutedArgs,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )

        let produced = await runtime.execute(
            reroutedCall,
            context: ToolExecutionContext(
                workspaceContext: context,
                policy: policy,
                executionScope: executionScope
            )
        )

        if shouldEmitMCPEditRequiredAfterRerouteFailure(events: produced) {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Unable to use coderide MCP editing tool '\(reroute.mcpTool)'. Verify MCP server/tool availability.",
                    reroutedTool: reroute.mcpTool
                )
            ]
        }

        return produced
    }

    private func shouldEmitMCPEditRequiredAfterRerouteFailure(events: [StreamEvent]) -> Bool {
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "mcp_tool_call", payload["status"] == "completed" {
                return false
            }
            if type == "tool_execution_error" {
                let errorCode = (payload["error_code"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if errorCode == "mcp_unavailable" || errorCode == "validation" {
                    return true
                }
            }
        }
        return false
    }

    private func mcpEditRequiredErrorEvent(
        originalTool: String,
        detail: String,
        reroutedTool: String?
    ) -> StreamEvent {
        var payload: [String: String] = [
            "title": "MCP-only editing policy violation",
            "detail": detail,
            "status": "failed",
            "error_code": "mcp_edit_required",
            "tool": originalTool,
        ]
        if let reroutedTool, !reroutedTool.isEmpty {
            payload["mcp_tool"] = reroutedTool
            payload["mcp_server"] = "coderide"
            payload["server_id"] = "coderide"
        }
        return .raw(type: "tool_validation_error", payload: payload)
    }

    struct MCPEditReroute: Sendable, Equatable {
        let mcpTool: String
        let args: [String: String]
    }

    static let mcpEditLikeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace",
        "apply_patch", "create_file", "delete_file",
        "parallel_apply", "find_and_replace_all",
        "rename_symbol", "undo_edit", "multi_edit",
        "multiedit",
    ]

    static func rerouteEditToolToMCP(toolName: String, args: [String: String]) -> MCPEditReroute? {
        func required(_ key: String) -> String? {
            let value = (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : args[key]
        }

        switch toolName.lowercased() {
        case "write":
            guard let path = required("path"), let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_write", args: [
                "path": path,
                "content": content,
            ])
        case "edit":
            if let path = required("path"),
               let oldString = args["old_string"],
               !oldString.isEmpty,
               let newString = args["new_string"] {
                return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                    "path": path,
                    "old_string": oldString,
                    "new_string": newString,
                ])
            }
            if let path = required("path"),
               let content = args["content"] {
                return MCPEditReroute(mcpTool: "coderide_write", args: [
                    "path": path,
                    "content": content,
                ])
            }
            return nil
        case "str_replace":
            guard let path = required("path"),
                  let oldString = args["old_string"], !oldString.isEmpty,
                  let newString = args["new_string"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                "path": path,
                "old_string": oldString,
                "new_string": newString,
            ])
        case "regex_replace":
            guard let path = required("path"),
                  let pattern = args["pattern"], !pattern.isEmpty,
                  let replacement = args["replacement"] else { return nil }
            var reroutedArgs: [String: String] = [
                "path": path,
                "pattern": pattern,
                "replacement": replacement,
            ]
            if let flags = required("flags") {
                reroutedArgs["flags"] = flags
            }
            return MCPEditReroute(mcpTool: "coderide_regex_replace", args: reroutedArgs)
        case "create_file":
            guard let path = required("path"),
                  let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_create_file", args: [
                "path": path,
                "content": content,
            ])
        default:
            return nil
        }
    }

    private func inferredToolName(from payload: [String: String]) -> String {
        let supportedTools: Set<String> = [
            "read", "glob", "grep", "edit", "write", "bash", "mcp", "web_search", "web_fetch",
            "str_replace", "create_file", "delete_file", "apply_patch",
            "read_range", "list_dir", "git_diff", "search_symbols", "run_tests", "build_project",
            "list_processes", "read_json", "write_json", "workspace_stats", "dependency_audit",
            "tail_log", "mcp_call", "mcp_list_tools", "mcp_describe_tool", "mcp_health",
            "mcp_list_servers", "mcp_reconnect",
            "todo_write", "todo_read", "plan_step_update", "mermaid_render", "policy_ack",
            "activate_plan_mode", "activate_debug_mode", "show_task_panel", "invoke_swarm", "show_swarm_panel",
            "debug_set_phase", "debug_request_user", "debug_resolve",
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
            if name == "debug_panel" {
                // Legacy hard-cut: never execute, always route to validation error.
                return name
            }
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

        You have access to powerful tools. Use tool calls to execute them.

        ## Mandatory Execution Workflow
        For EVERY task, follow this sequence strictly:
        1. **INVESTIGATE** — Use search/read tools (semantic_search, codebase_search, grep, glob, find_symbol, find_references, read, file_outline, web_search) to understand the problem BEFORE making changes.
        2. **REPORT** — State what you found: problems, root causes, affected files, scope. Be explicit.
        3. **TODO LIST** — For multi-step tasks, use the `todo_write` tool to create a structured task list in the LiveCard. This is mandatory for tasks with 3+ steps.
        4. **RESOLVE** — Fix issues one by one following the todo list. After each fix, verify. Update todo status as you go.
        5. **VERIFY & SUMMARIZE** — Run final verification. Report: what changed, which files, outcome.

        ## Core Principles
        1. ALWAYS read a file before editing it — understand current content first.
        2. Use `str_replace` for surgical edits (search-and-replace). ONLY use `write` for brand new files or complete rewrites.
        3. Prefer `semantic_search` for natural language queries ("where is auth handled?", "data saving flow").
        4. Prefer `codebase_search` and `find_symbol` over `grep` when looking for symbol definitions (classes, functions, structs). They use the index and are faster and more precise.
        5. Use `grep` for text/regex search. Use `glob` to find files by name pattern. Use `find_files` for fuzzy file name matching.
        6. Use `file_outline` to understand a file's structure before reading it entirely.
        7. Use `find_references` before refactoring to understand all usages of a symbol.
        8. Use `bash` ONLY for git operations, running commands, installing dependencies, builds, tests. Do NOT use bash for file operations (reading, searching, editing) — use the dedicated tools instead.
        9. After making changes, verify with `read_lints` (fast, no build) or `diagnostics` (full build). Prefer `read_lints` for quick checks.
        10. Use `parallel_apply` for making multiple independent edits across files in a single call.
        11. If AGENTS.md / SKILL.md / repository runbooks are present in the prompt/context, treat them as mandatory operational policy. Do not skip skill workflows.
        12. If the context contains a mandatory policy acknowledgment, use the `policy_ack` tool with the hash before any operational tool action.
        13. MCP availability verification is mandatory before MCP usage: `mcp_list_servers` first, then `mcp_list_tools`, then `mcp_describe_tool` (for unfamiliar tools), then `mcp_call`.
        14. Use `web_search` and `web_fetch` when you need current information, documentation, API references, or anything beyond your training data.
        15. When done, provide a clear summary: what changed, which files, outcome, and explicitly list MCP servers/tools used.
        16. Do NOT stop until the task is fully resolved or you've clearly stated a blocker with next steps.

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
        - **debug_hypothesize** — Propose or update a debug hypothesis (ID-based). Args: `action` (propose/update), `hypothesis_id` (required for update), `title` (required for propose), `description`, `status` (proposed/investigating/confirmed/rejected), `evidence`.
        - **debug_mark** — Insert a debug marker (print/log/assert) into a file. The marker is tagged with 🐛 DEBUG for easy cleanup. Args: `path`, `line` (line number), `comment` (description), `code` (optional code to insert).
        - **debug_clean** — Remove ALL debug markers (lines containing 🐛 DEBUG) from a file or entire workspace. Args: `path` (optional, cleans all files if omitted).

        ### Debug Flow (MCP-first, typed events)
        When debugging, use only the canonical typed debug tools for panel control:
        - `debug_set_phase` (phase: describing|reproducing|fixing|instrumenting|verifying|resolved, detail optional)
        - `debug_request_user` (kind: question|reproduce, prompt)
        - `debug_resolve` (summary)
        - `debug_panel` is legacy and invalid.

        **Phase 1: Describe**
        1. `debug_set_phase phase=describing`
        2. Gather context with `debug_context`
        3. Start/ensure session with `debug_session action=start`
        4. Log symptoms with `debug_log`

        **Phase 2: Reproduce**
        5. `debug_set_phase phase=reproducing`
        6. If user action is needed, call `debug_request_user kind=reproduce prompt=...`

        **Phase 3: Fix**
        7. `debug_set_phase phase=fixing`
        8. Hypothesize with `debug_hypothesize`
        9. Instrument with `debug_mark` and `debug_set_phase phase=instrumenting` when relevant
        10. Observe via `debug_log` + `debug_query`
        11. Apply minimal fix and update hypothesis status

        **Phase 4: Verify**
        12. `debug_set_phase phase=verifying`
        13. Verify via `read_lints` and targeted tests/diagnostics
        14. Clean instrumentation with `debug_clean`

        **Phase 5: Resolve**
        15. Resolve with `debug_resolve summary=...`
        16. Optionally mirror terminal phase with `debug_set_phase phase=resolved`

        ### Utility
        - **workspace_stats** — Get file/dir counts and size.
        - **dependency_audit** — Audit dependencies. Args: `manager` (swift/npm/pnpm/yarn).
        - **tail_log** — Read last N lines of a file. Args: `path`, `lines`.
        - **list_processes** — List running processes. Args: `filter`.

        ### IDE State Tools (LiveCard / panel control)
        - **todo_write** — Create or update a todo item in the LiveCard. Args: `title`, `status` (pending/in_progress/done/blocked), `priority` (low/medium/high), `notes` (optional), `activeForm` (optional present-tense label), `linkedFiles` (optional file paths).
        - **todo_read** — Read the current todo list. No required args.
        - **plan_step_update** — Update a plan step status. Args: `step_id`, `status` (pending/running/done/failed), `title` (optional).
        - **mermaid_render** — Render a Mermaid diagram in the LiveCard. Args: `code` (Mermaid syntax), `title` (optional).
        - **debug_set_phase** — Set debug pipeline phase. Args: `phase`, `detail` (optional).
        - **debug_request_user** — Request explicit user input in debug flow. Args: `kind` (question/reproduce), `prompt`.
        - **debug_resolve** — Resolve debug flow with summary. Args: `summary`.
        - **policy_ack** — Acknowledge a mandatory policy hash. Args: `hash`.
        - **activate_plan_mode** — Activate the plan panel. Args: `reason` (optional).
        - **activate_debug_mode** — Activate the debug panel. Args: `reason` (optional).
        - **show_task_panel** — Show the task panel. No required args.
        - **invoke_swarm** — Invoke a swarm agent for parallel work. Args: `task`.
        - **show_swarm_panel** — Open/focus swarm panel. Args: `swarm_id` (optional).
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

    // MARK: - Real-time tool start events

    /// Maps a tool name to the event type used for its "started" trace event.
    /// These types must pass ToolTraceVisibility and have isRunning == true.
    private static func toolStartEventType(for toolName: String) -> String {
        switch toolName {
        case "bash":
            return "command_execution"
        case "edit", "write", "str_replace", "create_file", "delete_file", "parallel_apply", "regex_replace",
             "apply_patch", "multi_edit", "multiedit",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return "file_change"
        case "web_search":
            return "web_search_started"
        case "web_fetch":
            return "web_fetch_started"
        default:
            return "read_batch_started"
        }
    }

    /// Builds a payload for the real-time "started" event emitted before tool execution.
    private static func toolStartPayload(for toolName: String, args: [String: String]) -> [String: String] {
        var payload: [String: String] = [
            "tool": toolName,
            "name": toolName,
            "status": "started",
            "tool_call_id": args["id"] ?? "",
        ]
        if let command = args["command"], !command.isEmpty {
            payload["command"] = command
            payload["title"] = "Bash"
            payload["detail"] = command
        }
        if let path = args["path"], !path.isEmpty { payload["path"] = path }
        if let query = args["query"], !query.isEmpty { payload["query"] = query }
        if let url = args["url"], !url.isEmpty { payload["url"] = url }
        if let server = args["server"] ?? args["server_id"], !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = args["swarm_id"], !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        if payload["title"] == nil {
            payload["title"] = toolStartTitle(for: toolName, args: args)
        }
        return payload
    }

    private static func toolStartTitle(for toolName: String, args: [String: String]) -> String {
        let pathComponent = { (key: String) -> String in
            ((args[key] ?? "") as NSString).lastPathComponent
        }
        switch toolName {
        case "bash":
            return "Bash"
        case "edit", "str_replace":
            let file = pathComponent("path")
            return file.isEmpty ? "Edit" : "Edit • \(file)"
        case "write", "create_file":
            let file = pathComponent("path")
            return file.isEmpty ? "Write" : "Write • \(file)"
        case "read", "read_range":
            let file = pathComponent("path")
            return file.isEmpty ? "Read" : "Read • \(file)"
        case "glob":
            let pattern = args["pattern"] ?? ""
            return pattern.isEmpty ? "Glob" : "Glob • \(pattern)"
        case "grep":
            let query = args["query"] ?? ""
            return query.isEmpty ? "Grep" : "Grep • \(query)"
        case "semantic_search":
            return "Semantic search"
        case "codebase_search":
            return "Codebase search"
        case "find_symbol":
            return "Find symbol"
        case "find_references":
            return "Find references"
        case "web_search":
            return "Web search"
        case "web_fetch":
            return "Fetching web page"
        case "diagnostics":
            return "Diagnostics"
        case "build_project":
            return "Building project"
        case "run_tests", "run_single_test":
            return "Running tests"
        default:
            return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
