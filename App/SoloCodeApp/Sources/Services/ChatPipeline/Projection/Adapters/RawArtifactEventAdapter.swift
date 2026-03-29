import Foundation

enum RawArtifactEventAdapter {
    static func events(
        rawType: String,
        payload: [String: String],
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        providerId: String
    ) -> [ChatPipelineEvent] {
        switch rawType {
        case "turn_started":
            return [make(.turnStarted, payload: payload, conversationId: conversationId, assistantMessageId: assistantMessageId, turnId: turnId, providerId: providerId)]
        case "reasoning":
            if ChatReasoningPresentationPolicy.mode(
                providerId: providerId,
                separateCodexThinkingMessagesEnabled: false
            ) == .suppressed {
                return []
            }
            guard let output = payload["output"], !output.isEmpty else { return [] }
            return [
                make(
                    .reasoningDelta,
                    payload: [
                        "output": output,
                        "group_id": payload["group_id"] ?? "reasoning",
                        "provider_id": providerId,
                    ],
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                ),
            ]
        case "mermaid_render":
            guard let code = payload["code"], !code.isEmpty else { return [] }
            return [
                make(
                    .mermaidArtifact,
                    payload: [
                        "artifact_id": "mermaid-\(stableIDSeed(code))",
                        "code": code,
                        "title": payload["title"] ?? "Diagram",
                        "provider_id": providerId,
                    ],
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                ),
            ]
        case "command_execution", "bash":
            guard let command = payload["command"], !command.isEmpty else { return [] }
            return [
                make(
                    .commandsArtifact,
                    payload: ["command": command, "provider_id": providerId],
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                ),
            ]
        case "file_change", "edit", "write", "apply_patch", "create_file", "delete_file":
            let directPath = payload["path"] ?? payload["file"] ?? ""
            let files = payload["files"]?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            let candidates = ([directPath] + files).filter { !$0.isEmpty }
            return candidates.map {
                make(
                    .filesArtifact,
                    payload: ["path": $0, "provider_id": providerId],
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                )
            }
        case "mcp_tool_call", "function_call",
             "read", "read_file", "fetch_file", "read_range", "file_read",
             "read_batch_completed", "read_batch_started",
             "grep", "search", "instant_grep", "glob", "list_dir", "find_files",
             "semantic_search", "codebase_search", "find_symbol", "find_references",
             "file_outline", "list_symbols",
             "mcp", "mcp_call",
             "web_search", "web_fetch",
             "skill", "agent", "run_agent", "sub_agent", "subagent":
            let toolName = payload["mcp_tool"]
                ?? payload["tool"]
                ?? payload["name"]
                ?? payload["title"]
                ?? rawType
            let cleanName = toolName
                .replacingOccurrences(of: "functions.", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { return [] }
            let detail = payload["detail"]
                ?? payload["arguments"]
                ?? ""
            let artifactId = payload["id"]
                ?? "tool-trace-\(stableIDSeed(cleanName + detail))"
            return [
                make(
                    .toolTraceArtifact,
                    payload: [
                        "artifact_id": artifactId,
                        "title": cleanName,
                        "detail": detail,
                        "provider_id": providerId,
                    ],
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                ),
            ]
        default:
            return []
        }
    }

    private static func make(
        _ kind: ChatPipelineEventKind,
        payload: [String: String],
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        providerId: String
    ) -> ChatPipelineEvent {
        ChatPipelineEvent(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            sequence: 0,
            source: providerId,
            kind: kind,
            payload: payload
        )
    }

    private static func stableIDSeed(_ input: String) -> String {
        var hasher = Hasher()
        hasher.combine(input)
        return String(abs(hasher.finalize()))
    }
}
