import Foundation

/// Provider che usa Claude Code CLI (`claude -p`)
public final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "claude-cli"
    public let displayName = "Claude Code CLI"
    
    private let claudePath: String
    
    public init(claudePath: String? = nil) {
        self.claudePath = claudePath ?? PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude"
    }
    
    public func isAuthenticated() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
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
        let path = claudePath
        let workspacePath = context.workspacePath
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(.error("Claude CLI non trovato a \(path). Installa da https://claude.com/code"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("claude"))
                        return
                    }
                    
                    let args = [
                        "-p", fullPrompt,
                        "--output-format", "stream-json",
                        "--allowedTools", "Read,Edit,Bash"
                    ]
                    
                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath
                    )
                    
                    continuation.yield(.started)
                    var fullContent = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        let eventType = json["type"] as? String ?? ""

                        if eventType == "stream_event",
                           let event = json["event"] as? [String: Any],
                           let delta = event["delta"] as? [String: Any],
                           (delta["type"] as? String) == "text_delta",
                           let text = delta["text"] as? String {
                            fullContent += text
                            continuation.yield(.textDelta(text))
                            if !didEmitShowTaskPanel, fullContent.contains(CoderIDEMarkers.showTaskPanel) {
                                didEmitShowTaskPanel = true
                                continuation.yield(.raw(type: "coderide_show_task_panel", payload: [:]))
                            }
                            if !didEmitInvokeSwarm, fullContent.contains(CoderIDEMarkers.invokeSwarmPrefix),
                               let start = fullContent.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                               let endRange = fullContent[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
                                didEmitInvokeSwarm = true
                                let task = String(fullContent[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !task.isEmpty {
                                    continuation.yield(.raw(type: "coderide_invoke_swarm", payload: ["task": task]))
                                }
                            }
                        }

                        if eventType == "assistant", let message = json["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            for block in content {
                                if let rawEvent = Self.parseToolUse(from: block) {
                                    continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                                }
                                if (block["type"] as? String) == "text", let text = block["text"] as? String, !text.isEmpty {
                                    if !fullContent.hasSuffix(text) {
                                        let newLen = fullContent.count
                                        fullContent += text
                                        let delta = String(fullContent.dropFirst(newLen))
                                        if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                                    }
                                    if !didEmitShowTaskPanel, fullContent.contains(CoderIDEMarkers.showTaskPanel) {
                                        didEmitShowTaskPanel = true
                                        continuation.yield(.raw(type: "coderide_show_task_panel", payload: [:]))
                                    }
                                    if !didEmitInvokeSwarm, fullContent.contains(CoderIDEMarkers.invokeSwarmPrefix),
                                       let start = fullContent.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                                       let endRange = fullContent[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
                                        didEmitInvokeSwarm = true
                                        let task = String(fullContent[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !task.isEmpty {
                                            continuation.yield(.raw(type: "coderide_invoke_swarm", payload: ["task": task]))
                                        }
                                    }
                                }
                            }
                        }

                        if eventType == "result", let resultText = json["result"] as? String, !resultText.isEmpty {
                            if resultText.count > fullContent.count {
                                let delta = String(resultText.dropFirst(fullContent.count))
                                fullContent = resultText
                                continuation.yield(.textDelta(delta))
                            } else {
                                fullContent = resultText
                            }
                            if !didEmitShowTaskPanel, fullContent.contains(CoderIDEMarkers.showTaskPanel) {
                                didEmitShowTaskPanel = true
                                continuation.yield(.raw(type: "coderide_show_task_panel", payload: [:]))
                            }
                            if !didEmitInvokeSwarm, fullContent.contains(CoderIDEMarkers.invokeSwarmPrefix),
                               let start = fullContent.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                               let endRange = fullContent[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
                                didEmitInvokeSwarm = true
                                let task = String(fullContent[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !task.isEmpty {
                                    continuation.yield(.raw(type: "coderide_invoke_swarm", payload: ["task": task]))
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

    private static func parseToolUse(from block: [String: Any]) -> (type: String, payload: [String: String])? {
        guard (block["type"] as? String) == "tool_use",
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any] else { return nil }

        switch name {
        case "Bash":
            let cmd = input["command"] as? String ?? input["command_line"] as? String ?? ""
            let title = "Bash • \(String(cmd.prefix(50)))\(cmd.count > 50 ? "..." : "")"
            return ("command_execution", [
                "title": title,
                "detail": cmd,
                "command": String(cmd.prefix(80))
            ])
        case "Edit", "Write":
            let path = input["file_path"] as? String ?? input["path"] as? String ?? "file"
            let base = (path as NSString).lastPathComponent
            let oldStr = input["old_string"] as? String ?? ""
            let newStr = input["new_string"] as? String ?? input["contents"] as? String ?? ""
            let oldLines = oldStr.components(separatedBy: .newlines).count
            let newLines = newStr.components(separatedBy: .newlines).count
            let added = max(0, newLines - oldLines)
            let removed = max(0, oldLines - newLines)
            let title = "Edit • \(base) • +\(added) -\(removed) lines"
            var payload: [String: String] = ["title": title, "detail": path, "path": path, "file": path]
            if added > 0 { payload["linesAdded"] = "\(added)" }
            if removed > 0 { payload["linesRemoved"] = "\(removed)" }
            return ("file_change", payload)
        case "Read":
            let path = input["path"] as? String ?? input["file_path"] as? String ?? ""
            let title = "Read • \((path as NSString).lastPathComponent)"
            return ("file_change", ["title": title, "detail": path, "path": path, "file": path])
        default:
            let title = name
            let detail = (input["query"] as? String) ?? (input["command"] as? String) ?? ""
            return ("mcp_tool_call", ["title": title, "detail": detail, "tool": name])
        }
    }
}
