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
        runtime: UnifiedToolRuntime = UnifiedToolRuntime(),
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent,
        maxToolRounds: Int = 8
    ) {
        self.base = base
        self.id = base.id
        self.displayName = base.displayName
        self.runtime = runtime
        self.policy = policy
        self.executionScope = executionScope
        self.maxToolRounds = max(1, maxToolRounds)
    }

    public func isAuthenticated() -> Bool {
        base.isAuthenticated()
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
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
                        let stream = try await base.send(
                            prompt: currentPrompt, context: context,
                            imageURLs: isFirstRound ? imageURLs : nil)
                        var roundText = ""
                        var roundToolResults: [[String: String]] = []

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                roundText += delta
                                continuation.yield(.textDelta(delta))
                                let markers = CoderIDEMarkerParser.parse(from: roundText)
                                for marker in markers {
                                    let dedupeId =
                                        marker.payload["id"]
                                        ?? "\(marker.kind)|\(marker.payload.description)"
                                    if emittedMarkerIds.contains(dedupeId) { continue }
                                    emittedMarkerIds.insert(dedupeId)

                                    let produced = await events(for: marker, context: context)
                                    for e in produced {
                                        continuation.yield(e)
                                    }
                                    if marker.kind == "tool_call",
                                        let summary = summarizeToolResultEvents(
                                            produced, marker: marker)
                                    {
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
                                    let isPartial =
                                        (payload["is_partial"] ?? "").lowercased() == "true"
                                    if isPartial { continue }
                                    let name =
                                        payload["name"]?.trimmingCharacters(
                                            in: .whitespacesAndNewlines) ?? ""
                                    if name.isEmpty { continue }
                                    var args: [String: String] = [:]
                                    if let argsJson = payload["args"],
                                        let parsed = parseArgsJSON(argsJson)
                                    {
                                        args = parsed
                                    }
                                    args["id"] = payload["id"] ?? UUID().uuidString
                                    args["name"] = name
                                    let marker = CoderIDEMarker(kind: "tool_call", payload: args)
                                    let produced = await events(for: marker, context: context)
                                    for e in produced {
                                        continuation.yield(e)
                                    }
                                    if let summary = summarizeToolResultEvents(
                                        produced, marker: marker)
                                    {
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
                        if roundToolResults.isEmpty {
                            break
                        }
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

    private func summarizeToolResultEvents(_ events: [StreamEvent], marker: CoderIDEMarker)
        -> [String: String]?
    {
        var summary: [String: String] = [
            "id": marker.payload["id"] ?? UUID().uuidString,
            "name": marker.payload["name"] ?? "",
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

    private func buildFollowUpPrompt(
        originalPrompt: String, transcript: String, toolResults: [[String: String]]
    ) -> String {
        let formattedResults = toolResults.map { result in
            let id = result["id"] ?? "-"
            let name = result["name"] ?? "-"
            let status = result["status"] ?? "unknown"
            let detail = result["detail"] ?? ""
            let path = result["path"].map { "\npath: \($0)" } ?? ""
            let output = result["output"].map { "\noutput (truncated):\n\($0)" } ?? ""
            return
                "- tool_call id=\(id), name=\(name), status=\(status)\n  detail: \(detail)\(path)\(output)"
        }.joined(separator: "\n")

        return """
            \(toolProtocolPrompt)

            ## Context

            **Original user request:**
            \(originalPrompt)

            **Conversation so far:**
            \(transcript)

            **Tool results just executed:**
            \(formattedResults)

            ## Instructions

            Continue working on the user's request using the tool results above.
            - If you need more information, call additional tools using [CODERIDE:tool_call|...] markers.
            - If you have enough information, provide your final answer to the user.
            - Do NOT repeat tool calls that already succeeded.
            """
    }

    private func parseArgsJSON(_ raw: String) -> [String: String]? {
        guard let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let dict = obj as? [String: Any]
        else {
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

    private func events(for marker: CoderIDEMarker, context: WorkspaceContext) async
        -> [StreamEvent]
    {
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
            return [.raw(type: "read_batch_started", payload: marker.payload)]
        case "web_search":
            return [.raw(type: "web_search_started", payload: marker.payload)]
        case "tool_call":
            let toolName =
                marker.payload["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !toolName.isEmpty else {
                return [
                    .raw(
                        type: "tool_validation_error",
                        payload: [
                            "title": "Tool call invalida",
                            "detail": "Campo name mancante in marker tool_call",
                            "status": "failed",
                        ])
                ]
            }
            let call = ToolCall(
                id: marker.payload["id"] ?? UUID().uuidString,
                name: toolName,
                args: marker.payload,
                sourceProvider: id,
                swarmId: marker.payload["swarm_id"],
                scope: executionScope
            )
            return await runtime.execute(
                call,
                context: ToolExecutionContext(
                    workspaceContext: context, policy: policy, executionScope: executionScope))
        default:
            return []
        }
    }

    private var toolProtocolPrompt: String {
        """
        You have access to workspace tools via structured markers. To use a tool, emit it **exactly** in this format (one marker per tool call):

        [CODERIDE:tool_call|id=<unique-id>|name=<TOOL_NAME>|<arg1>=<value1>|<arg2>=<value2>]

        ### Available tools

        | Tool | Required args | Description |
        |------|--------------|-------------|
        | `read` | path | Read a file's content. Use this before editing to see current state. |
        | `ls` | path | List directory contents. Use to explore project structure. |
        | `glob` | pattern | Find files matching a pattern (e.g. `*.swift`, `**/*.ts`). |
        | `grep` | query, pathScope (optional) | Search text/regex in files. Returns matching lines with file:line:content. |
        | `edit` | path, content | Write full content to a file (creates parent dirs if needed). Best for new files or complete rewrites. |
        | `patch` | path, search, replace | Surgical edit: find exact `search` text in file and replace with `replace`. Best for modifying existing files. |
        | `bash` | command | Run a shell command in the workspace directory. |
        | `mkdir` | path | Create a directory (with parents). |
        | `web_search` | query | Search the web for information. |

        ### Important rules
        - Always `read` a file before `patch`-ing it so you know the exact text to search for.
        - Use `patch` (not `edit`) for modifying existing files — it's safer and preserves unchanged content.
        - Use `edit` only for creating new files or when you need to rewrite the entire file.
        - For `patch`, the `search` value must be an **exact** substring of the file content (including whitespace/indentation).
        - Each marker must have a unique `id` (use any short string like `t1`, `t2`, etc.).
        - Escape `|` as `\\|`, `]` as `\\]`, and `\\` as `\\\\` inside argument values.

        ### Example usage

        Read a file:
        [CODERIDE:tool_call|id=t1|name=read|path=src/main.swift]

        Search for a pattern:
        [CODERIDE:tool_call|id=t2|name=grep|query=func handleError|pathScope=Sources]

        Patch a file (surgical edit):
        [CODERIDE:tool_call|id=t3|name=patch|path=src/main.swift|search=let x = 5|replace=let x = 10]

        Run a command:
        [CODERIDE:tool_call|id=t4|name=bash|command=swift build 2>&1]

        ### Additional markers (for IDE integration)
        [CODERIDE:todo_write|title=...|status=pending|priority=medium|notes=...|files=a.swift,b.swift]
        [CODERIDE:todo_read]
        [CODERIDE:instant_grep|query=...|pathScope=...|matchesCount=...|previewLines=...]
        [CODERIDE:plan_step|step_id=...|status=running]
        [CODERIDE:read_batch|count=...|files=...|group_id=...]
        [CODERIDE:web_search|queryId=...|query=...|status=started|group_id=...]
        """
    }
}
