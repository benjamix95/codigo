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
    private let environmentOverride: [String: String]?

    public init(
        claudePath: String? = nil,
        model: String? = nil,
        allowedTools: [String] = ["Read", "Edit", "Bash"],
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        self.claudePath = claudePath ?? PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude"
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
        self.allowedTools = Self.normalizeTools(allowedTools)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }
    
    public func isAuthenticated() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
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
                    
                    var env = CodexDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }
                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    var fullContent = ""
                    var accumulatedThinking = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var emittedMarkers = Set<String>()
                    var markerCarry = ""

                    for try await line in stream {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        let eventType = json["type"] as? String ?? ""

                        if eventType == "stream_event",
                           let event = json["event"] as? [String: Any],
                           let delta = event["delta"] as? [String: Any] {
                            if (delta["type"] as? String) == "thinking_delta",
                               let thinkingChunk = delta["thinking"] as? String, !thinkingChunk.isEmpty {
                                accumulatedThinking += thinkingChunk
                                let text = String(accumulatedThinking.prefix(6_000))
                                continuation.yield(.raw(type: "reasoning", payload: [
                                    "output": text,
                                    "title": "Ragionamento",
                                    "group_id": "reasoning-stream"
                                ]))
                            }
                            if (delta["type"] as? String) == "text_delta",
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
                            for markerEvent in Self.parseCoderIDEMarkerEvents(in: text, carry: &markerCarry) {
                                let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                if emittedMarkers.insert(key).inserted {
                                    continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
                                }
                            }
                            }
                        }

                        if eventType == "assistant", let message = json["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            for block in content {
                                if let rawEvent = Self.parseToolUse(from: block) {
                                    continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                                }
                                if (block["type"] as? String) == "thinking",
                                   let thinkingText = (block["thinking"] as? String) ?? (block["text"] as? String), !thinkingText.isEmpty {
                                    continuation.yield(.raw(type: "reasoning", payload: [
                                        "output": String(thinkingText.prefix(6_000)),
                                        "title": "Ragionamento",
                                        "group_id": "reasoning-stream"
                                    ]))
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
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: text, carry: &markerCarry) {
                                        let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                        if emittedMarkers.insert(key).inserted {
                                            continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
                                        }
                                    }
                                }
                            }
                        }

                        if eventType == "result", let resultText = json["result"] as? String, !resultText.isEmpty {
                            let previousFullContent = fullContent
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
                            let suffix = resultText.count > previousFullContent.count
                                ? String(resultText.dropFirst(previousFullContent.count))
                                : ""
                            for markerEvent in Self.parseCoderIDEMarkerEvents(in: suffix, carry: &markerCarry) {
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
            let cmd = firstString(in: input, keys: ["command", "command_line", "cmd"]) ?? ""
            let title = "Bash • \(String(cmd.prefix(50)))\(cmd.count > 50 ? "..." : "")"
            var payload: [String: String] = [
                "title": title,
                "detail": cmd,
                "command": cmd
            ]
            if let cwd = firstString(in: input, keys: ["cwd", "working_directory", "workdir"]) {
                payload["cwd"] = cwd
            }
            if let output = firstString(in: input, keys: ["output", "result", "stdout", "message", "content"]) {
                payload["output"] = String(output.prefix(6_000))
            }
            if let stderr = firstString(in: input, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
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
            if !oldStr.isEmpty || !newStr.isEmpty {
                payload["diffPreview"] = buildDiffPreview(old: oldStr, new: newStr)
            }
            return ("file_change", payload)
        case "Read":
            let path = input["path"] as? String ?? input["file_path"] as? String ?? ""
            var payload: [String: String] = [
                "title": "Read • \((path as NSString).lastPathComponent)",
                "detail": path,
                "path": path,
                "file": path,
                "count": "1",
                "files": path
            ]
            if let out = firstString(in: input, keys: ["content", "output", "result"]), !out.isEmpty {
                payload["output"] = String(out.prefix(6_000))
            }
            return ("read_batch_completed", payload)
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

    private static func parseCoderIDEMarkerEvents(in text: String, carry: inout String) -> [(type: String, payload: [String: String])] {
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
            case "read_batch":
                events.append((type: "read_batch_started", payload: marker.payload))
            case "web_search":
                events.append((type: "web_search_started", payload: marker.payload))
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

    private static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key], let stringValue = stringify(value), !stringValue.isEmpty {
                return stringValue
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

    private static func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        let maxCount = min(max(oldLines.count, newLines.count), 80)
        for i in 0..<maxCount {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            if oldLine == newLine { continue }
            if let oldLine { out.append("- \(oldLine)") }
            if let newLine { out.append("+ \(newLine)") }
            if out.count >= 40 { break }
        }
        return out.joined(separator: "\n")
    }
}
