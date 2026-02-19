import Foundation

/// Provider che usa Claude Code CLI (`claude -p`)
public final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "claude-cli"
    public let displayName = "Claude Code CLI"
    
    private let claudePath: String
    private let model: String?
    private let allowedTools: [String]
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope

    public init(
        claudePath: String? = nil,
        model: String? = nil,
        allowedTools: [String] = ["Read", "Edit", "Bash"],
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent
    ) {
        self.claudePath = claudePath ?? PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude"
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
        self.allowedTools = Self.normalizeTools(allowedTools)
        self.executionController = executionController
        self.executionScope = executionScope
    }
    
    public func isAuthenticated() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
        process.standardOutput = nil
        process.standardError = nil
        process.environment = CodexDetector.shellEnvironment()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        var fullPrompt = prompt + context.contextPrompt()
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Immagine: \($0.path)]" }.joined(separator: "\n")
            fullPrompt = refs + "\n\n" + fullPrompt
        }
        let path = claudePath
        let workspacePath = context.workspacePath
        let model = self.model
        let allowedTools = self.allowedTools
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(.error("Claude CLI non trovato a \(path). Installa da https://claude.com/code"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("claude"))
                        return
                    }
                    
                    var args = [
                        "-p", fullPrompt,
                        "--output-format", "stream-json"
                    ]
                    if let model {
                        args += ["--model", model]
                    }
                    if !allowedTools.isEmpty {
                        args += ["--allowedTools", allowedTools.joined(separator: ",")]
                    }
                    
                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: CodexDetector.shellEnvironment(),
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    var fullContent = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var emittedMarkers = Set<String>()

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
                            for markerEvent in Self.parseCoderIDEMarkerEvents(in: text) {
                                let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                if emittedMarkers.insert(key).inserted {
                                    continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
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
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: text) {
                                        let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                        if emittedMarkers.insert(key).inserted {
                                            continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
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
                            let suffix = resultText.count > fullContent.count
                                ? String(resultText.dropFirst(fullContent.count))
                                : resultText
                            for markerEvent in Self.parseCoderIDEMarkerEvents(in: suffix) {
                                let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                if emittedMarkers.insert(key).inserted {
                                    continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
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
            var payload: [String: String] = [
                "title": title,
                "detail": cmd,
                "command": String(cmd.prefix(80))
            ]
            if let cwd = input["cwd"] as? String ?? input["working_directory"] as? String {
                payload["cwd"] = cwd
            }
            if let output = input["output"] as? String ?? input["result"] as? String ?? input["stdout"] as? String {
                payload["output"] = String(output.prefix(6_000))
            }
            if let stderr = input["stderr"] as? String, !stderr.isEmpty {
                payload["stderr"] = String(stderr.prefix(3_000))
            }
            return ("command_execution", payload)
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

    private static func normalizeTools(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result.isEmpty ? ["Read", "Edit", "Bash"] : result
    }

    private static func parseCoderIDEMarkerEvents(in text: String) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []
        if text.contains(CoderIDEMarkers.todoRead) {
            events.append((type: "todo_read", payload: [:]))
        }
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.todoWritePrefix, mappedType: "todo_write")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.instantGrepPrefix, mappedType: "instant_grep")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.planStepPrefix, mappedType: "plan_step_update")
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
}
