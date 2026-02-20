import Foundation

/// Provider che usa Gemini CLI (`gemini -p`)
public final class GeminiCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"

    private let geminiPath: String
    private let modelOverride: String?
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        geminiPath: String? = nil,
        modelOverride: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        self.geminiPath = geminiPath ?? GeminiDetector.findGeminiPath(customPath: nil) ?? "/opt/homebrew/bin/gemini"
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public func isAuthenticated() -> Bool {
        guard FileManager.default.fileExists(atPath: geminiPath) else { return false }
        return GeminiDetector.checkAuth(geminiPath: geminiPath)
    }

    private func shellEnvironment() -> [String: String] {
        var env = GeminiDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        return env
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let path = geminiPath
        let workspacePath = context.workspacePath

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(.error("Gemini CLI non trovato a \(path)."))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("gemini"))
                        return
                    }

                    let env = shellEnvironment()

                    var args: [String]
                    if let model = modelOverride, !model.isEmpty {
                        args = ["-m", model, "-p", fullPrompt, "--output-format", "json"]
                    } else {
                        args = ["-p", fullPrompt, "--output-format", "json"]
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
                    var fullText = ""
                    var didEmitShowTaskPanel = false
                    var didEmitInvokeSwarm = false
                    var emittedMarkers = Set<String>()
                    for try await line in stream {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let rawEvent = Self.parseRawEvent(from: json) {
                                continuation.yield(.raw(type: rawEvent.type, payload: rawEvent.payload))
                            }
                            if let usage = json["usage"] as? [String: Any] {
                                let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int) ?? -1
                                let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int) ?? -1
                                continuation.yield(.raw(type: "usage", payload: [
                                    "input_tokens": "\(input)",
                                    "output_tokens": "\(output)",
                                    "model": "gemini-cli"
                                ]))
                            }
                            if let text = Self.extractText(from: json), !text.isEmpty {
                                let delta = text.hasPrefix(fullText) ? String(text.dropFirst(fullText.count)) : text
                                fullText = text
                                if !delta.isEmpty {
                                    continuation.yield(.textDelta(delta))
                                    if !didEmitShowTaskPanel, fullText.contains(CoderIDEMarkers.showTaskPanel) {
                                        didEmitShowTaskPanel = true
                                        continuation.yield(.raw(type: "coderide_show_task_panel", payload: [:]))
                                    }
                                    if !didEmitInvokeSwarm, fullText.contains(CoderIDEMarkers.invokeSwarmPrefix),
                                       let start = fullText.range(of: CoderIDEMarkers.invokeSwarmPrefix)?.upperBound,
                                       let endRange = fullText[start...].range(of: CoderIDEMarkers.invokeSwarmSuffix) {
                                        didEmitInvokeSwarm = true
                                        let task = String(fullText[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !task.isEmpty {
                                            continuation.yield(.raw(type: "coderide_invoke_swarm", payload: ["task": task]))
                                        }
                                    }
                                    for markerEvent in Self.parseCoderIDEMarkerEvents(in: delta) {
                                        let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                        if emittedMarkers.insert(key).inserted {
                                            continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
                                        }
                                    }
                                }
                                continue
                            }
                        }
                        continuation.yield(.textDelta(line + "\n"))
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

    private static func parseRawEvent(from json: [String: Any]) -> (type: String, payload: [String: String])? {
        let item = (json["item"] as? [String: Any]) ?? json
        let type = firstString(in: item, keys: ["type", "event_type"])?.lowercased() ?? ""

        if type.contains("command") || type.contains("bash") || firstString(in: item, keys: ["command", "command_line", "cmd"]) != nil {
            var payload: [String: String] = [
                "title": "Bash",
                "detail": firstString(in: item, keys: ["command", "command_line", "cmd"]) ?? ""
            ]
            if let command = firstString(in: item, keys: ["command", "command_line", "cmd"]) { payload["command"] = command }
            if let cwd = firstString(in: item, keys: ["cwd", "working_directory", "workdir"]) { payload["cwd"] = cwd }
            if let output = firstString(in: item, keys: ["output", "result", "stdout"]) { payload["output"] = String(output.prefix(6_000)) }
            if let stderr = firstString(in: item, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
                payload["stderr"] = String(stderr.prefix(3_000))
            }
            if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId; payload["group_id"] = "swarm-\(swarmId)" }
            return ("command_execution", payload)
        }

        if type.contains("edit") || type.contains("write") || type.contains("file_change") {
            let path = firstString(in: item, keys: ["path", "file_path", "file", "target_path"]) ?? "file"
            var payload: [String: String] = [
                "title": "Edit • \((path as NSString).lastPathComponent)",
                "detail": path,
                "path": path,
                "file": path
            ]
            if let out = firstString(in: item, keys: ["diff", "diff_preview", "patch"]), !out.isEmpty {
                payload["diffPreview"] = String(out.prefix(6_000))
            }
            if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId; payload["group_id"] = "swarm-\(swarmId)" }
            return ("file_change", payload)
        }

        if type == "reasoning" || type == "thinking" {
            let text = firstString(in: item, keys: ["text", "output", "content", "result", "message"]) ?? ""
            guard !text.isEmpty else { return nil }
            var payload: [String: String] = [
                "title": "Ragionamento",
                "detail": String(text.prefix(200)) + (text.count > 200 ? "…" : ""),
                "output": String(text.prefix(6_000)),
                "group_id": "reasoning-stream"
            ]
            if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId }
            return ("reasoning", payload)
        }

        if type.contains("read") {
            let path = firstString(in: item, keys: ["path", "file_path", "file"]) ?? ""
            guard !path.isEmpty else { return nil }
            var payload: [String: String] = [
                "title": "Read • \((path as NSString).lastPathComponent)",
                "detail": path,
                "path": path,
                "file": path,
                "count": "1",
                "files": path
            ]
            if let output = firstString(in: item, keys: ["output", "result", "content"]) { payload["output"] = String(output.prefix(6_000)) }
            if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId; payload["group_id"] = "swarm-\(swarmId)" }
            return ("read_batch_completed", payload)
        }

        return nil
    }

    private static func extractText(from obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            for key in ["text", "result", "content", "message"] {
                if let value = dict[key], let txt = stringify(value), !txt.isEmpty {
                    return txt
                }
            }
            for (_, value) in dict {
                if let nested = extractText(from: value), !nested.isEmpty {
                    return nested
                }
            }
        } else if let arr = obj as? [Any] {
            var chunks: [String] = []
            for value in arr {
                if let nested = extractText(from: value), !nested.isEmpty {
                    chunks.append(nested)
                }
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        return nil
    }

    private static func parseCoderIDEMarkerEvents(in text: String) -> [(type: String, payload: [String: String])] {
        var events: [(type: String, payload: [String: String])] = []
        if text.contains(CoderIDEMarkers.todoRead) {
            events.append((type: "todo_read", payload: [:]))
        }
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.todoWritePrefix, mappedType: "todo_write")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.instantGrepPrefix, mappedType: "instant_grep")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.planStepPrefix, mappedType: "plan_step_update")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.readBatchPrefix, mappedType: "read_batch_started")
        events += parseMarkerList(text: text, prefix: CoderIDEMarkers.webSearchPrefix, mappedType: "web_search_started")
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
                if let c = dict["content"] as? String { return c }
                return nil
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let o = dict["output"] as? String { return o }
            if let c = dict["content"] as? String { return c }
            if let e = dict["error"] as? String { return e }
        }
        return nil
    }
}
