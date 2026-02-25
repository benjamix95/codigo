import Foundation

/// Provider that uses Gemini CLI (`gemini -p`)
public final class GeminiCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )

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
        let fullPrompt = SystemPrompts.taskCompletionStrict + "\n\n" + prompt + context.contextPrompt()
        let path = geminiPath
        let workspacePath = context.workspacePath

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.yield(.error("Gemini CLI not found at \(path)."))
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
                    var markerCarry = ""
                    var jsonCarry = ""

                    func consumeJSON(_ json: [String: Any]) {
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
                                for markerEvent in Self.parseCoderIDEMarkerEvents(in: delta, carry: &markerCarry) {
                                    let key = "\(markerEvent.type)|\(markerEvent.payload.description)"
                                    if emittedMarkers.insert(key).inserted {
                                        continuation.yield(.raw(type: markerEvent.type, payload: markerEvent.payload))
                                    }
                                }
                            }
                        }
                    }

                    for try await line in stream {
                        let payloads = Self.parseStreamJSONPayloads(from: line, carry: &jsonCarry)
                        if !payloads.isEmpty {
                            for json in payloads {
                                consumeJSON(json)
                            }
                            continue
                        }

                        // Avoid showing partial JSON noise (e.g. multiline pretty-printed output).
                        if !jsonCarry.isEmpty || Self.looksLikeJSONFragment(line) {
                            continue
                        }
                        continuation.yield(.textDelta(line + "\n"))
                    }
                    for json in Self.flushStreamJSONPayloads(carry: &jsonCarry) {
                        consumeJSON(json)
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    let message = Self.userFacingErrorMessage(from: error)
                    continuation.yield(.error(message))
                    continuation.finish(throwing: CoderEngineError.apiError(message))
                }
            }
        }
    }

    private static func parseRawEvent(from json: [String: Any]) -> (type: String, payload: [String: String])? {
        let item = (json["item"] as? [String: Any]) ?? json
        let type = firstString(in: item, keys: ["type", "event_type"])?.lowercased() ?? ""
        if type == "reasoning" || type == "thinking" {
            let text = firstString(in: item, keys: ["text", "output", "content", "result", "message"]) ?? ""
            guard !text.isEmpty else { return nil }
            var payload: [String: String] = [
                "title": "Reasoning",
                "detail": String(text.prefix(200)) + (text.count > 200 ? "…" : ""),
                "output": String(text.prefix(6_000)),
                "group_id": "reasoning-stream"
            ]
            if let swarmId = firstString(in: item, keys: ["swarm_id"]) { payload["swarm_id"] = swarmId }
            return ("reasoning", payload)
        }

        let rawTool = firstString(in: item, keys: ["tool", "name"]) ?? type
        if let mapped = ProviderToolEventMapper.map(
            toolName: rawTool,
            payload: item,
            typeHint: type
        ) {
            return withSwarmMetadata(mapped, item: item)
        }

        if !type.isEmpty {
            if let mappedFromType = ProviderToolEventMapper.map(
                toolName: type,
                payload: item,
                typeHint: type
            ) {
                return withSwarmMetadata(mappedFromType, item: item)
            }
        }

        return nil
    }

    private static func withSwarmMetadata(
        _ mapped: (type: String, payload: [String: String]),
        item: [String: Any]
    ) -> (type: String, payload: [String: String]) {
        var payload = mapped.payload
        if let swarmId = firstString(in: item, keys: ["swarm_id"]), !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = payload["group_id"] ?? "swarm-\(swarmId)"
        }
        return (mapped.type, payload)
    }

    static func parseStreamJSONPayloads(from rawLine: String, carry: inout String) -> [[String: Any]] {
        let cleaned = cleanedJSONCandidateLine(rawLine)
        guard !cleaned.isEmpty else { return [] }

        if let direct = decodeJSONDictionary(cleaned) {
            return [direct]
        }

        // Handle concatenated/noisy objects only when the line appears to contain
        // top-level JSON objects, avoiding nested objects from pretty-printed lines.
        if let first = cleaned.first, first == "{" {
            let inlinePayloads = extractJSONObjectStrings(from: cleaned).compactMap { decodeJSONDictionary($0) }
            if !inlinePayloads.isEmpty {
                return inlinePayloads
            }
        }

        if !carry.isEmpty || looksLikeJSONFragment(cleaned) {
            if !carry.isEmpty {
                carry.append("\n")
            }
            carry.append(cleaned)

            if let full = decodeJSONDictionary(carry) {
                carry = ""
                return [full]
            }

            // Safety valve: prevent unbounded buffer growth on unexpected output.
            if carry.count > 200_000 {
                carry = String(carry.suffix(50_000))
            }
        }

        return []
    }

    static func flushStreamJSONPayloads(carry: inout String) -> [[String: Any]] {
        let cleaned = carry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            carry = ""
            return []
        }
        if let full = decodeJSONDictionary(cleaned) {
            carry = ""
            return [full]
        }
        let payloads = extractJSONObjectStrings(from: cleaned).compactMap { decodeJSONDictionary($0) }
        carry = ""
        return payloads
    }

    static func extractText(from obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            // Prefer canonical Gemini response fields and avoid metadata.
            for key in ["response", "result", "output", "text"] {
                if let value = dict[key], let txt = nonEmptyString(value) {
                    return txt
                }
            }

            for key in ["content", "message"] {
                if let value = dict[key], let txt = nonEmptyString(value) {
                    return txt
                }
            }

            let metadataKeys: Set<String> = [
                "session_id", "id", "status", "stats", "models", "model", "tools", "files",
                "usage", "tokens", "api", "totalrequests", "totalerrors", "totallatencyms",
                "prompt", "input", "cached", "thoughts", "candidates", "total", "durationms"
            ]
            for (key, value) in dict {
                if metadataKeys.contains(key.lowercased()) {
                    continue
                }
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

    private static func looksLikeJSONFragment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let first = trimmed.first, ["{", "}", "[", "]", "\"", ","].contains(first) {
            return true
        }
        return trimmed.contains("\":")
    }

    private static func cleanedJSONCandidateLine(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeJSONDictionary(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func extractJSONObjectStrings(from line: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var startIndex: String.Index?

        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = line.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
                index = line.index(after: index)
                continue
            }

            if ch == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let end = line.index(after: index)
                        results.append(String(line[start..<end]))
                        startIndex = nil
                    }
                }
            }

            index = line.index(after: index)
        }

        return results
    }

    static func parseCoderIDEMarkerEvents(in text: String, carry: inout String) -> [(type: String, payload: [String: String])] {
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
            case "debug_panel":
                events.append((type: "debug_panel_update", payload: marker.payload))
            case "read_batch":
                events.append((type: "read_batch_started", payload: marker.payload))
            case "web_search":
                events.append((type: "web_search_started", payload: marker.payload))
            case "web_fetch":
                events.append((type: "web_fetch_started", payload: marker.payload))
            case "policy_ack":
                events.append((type: "policy_ack", payload: marker.payload))
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

    private static func firstInt(in input: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = input[key] else { continue }
            if let intValue = intValue(from: value) {
                return intValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstInt(in: nested, keys: keys) {
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

    private static func intValue(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func fileChangeTitle(path: String, changeType: String) -> String {
        let basename = (path as NSString).lastPathComponent.isEmpty
            ? "file"
            : (path as NSString).lastPathComponent
        let normalized = changeType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("create")
            || normalized == "a"
            || normalized == "add"
            || normalized == "added"
            || normalized == "create_file"
        {
            return "Created \(basename)"
        }
        if normalized.contains("delete")
            || normalized.contains("remove")
            || normalized == "d"
            || normalized == "deleted"
        {
            return "Deleted \(basename)"
        }
        return "Edited \(basename)"
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value, let text = stringify(value) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func userFacingErrorMessage(from error: Error) -> String {
        if let cancellation = error as? CancellationError {
            return cancellation.localizedDescription
        }

        let processError = error as? ProcessRunner.ProcessRunnerError
        let candidates = [
            processError?.message,
            processError?.stdoutTail,
            error.localizedDescription,
        ].compactMap { $0 }.filter { !$0.isEmpty }

        for candidate in candidates {
            if let parsed = parseGeminiCLIErrorMessage(from: candidate) {
                return parsed
            }
        }

        return error.localizedDescription
    }

    static func parseGeminiCLIErrorMessage(from raw: String) -> String? {
        let objects = extractJSONObjectStrings(from: raw)
        for object in objects.reversed() {
            guard let dict = decodeJSONDictionary(object) else { continue }
            if let message = geminiErrorMessage(from: dict, raw: raw) {
                return message
            }
        }

        if raw.contains("[object Object]"), let http = firstHTTPStatusCode(in: raw) {
            if http == 404 {
                return "Gemini CLI: HTTP 404 error (resource/model not found). Check the selected model or update the CLI."
            }
            return "Gemini CLI: HTTP error \(http)."
        }

        return nil
    }

    private static func geminiErrorMessage(from json: [String: Any], raw: String) -> String? {
        let topError = json["error"] as? [String: Any]
        let topMessage = nonEmptyString(topError?["message"]) ?? nonEmptyString(json["message"])
        let topCode = nonEmptyString(topError?["code"]) ?? nonEmptyString(json["code"])

        let httpCode = firstHTTPStatusCode(in: raw)
            ?? intValue(topCode)
            ?? intValue(nonEmptyString(json["status"]))

        let cleanedMessage = cleanedGeminiErrorMessage(topMessage)

        if let code = httpCode, code == 404 {
            if let cleanedMessage, !cleanedMessage.isEmpty {
                return "Gemini CLI: HTTP 404 error — \(cleanedMessage)"
            }
            return "Gemini CLI: HTTP 404 error (resource/model not found). Check the selected model or update the CLI."
        }

        if let code = httpCode {
            if let cleanedMessage, !cleanedMessage.isEmpty {
                return "Gemini CLI: HTTP error \(code) — \(cleanedMessage)"
            }
            return "Gemini CLI: HTTP error \(code)."
        }

        if let cleanedMessage, !cleanedMessage.isEmpty {
            return "Gemini CLI: \(cleanedMessage)"
        }

        if raw.contains("[object Object]") {
            return "Gemini CLI: request failed (no detailed error). Check account and model configuration."
        }

        return nil
    }

    private static func cleanedGeminiErrorMessage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "[object Object]" { return nil }
        return trimmed
    }

    private static func firstHTTPStatusCode(in text: String) -> Int? {
        let patterns = [
            #"(?i)\bhttp\s*([45]\d{2})\b"#,
            #"(?i)\bstatus(?:\s*code)?\s*[:=]?\s*([45]\d{2})\b"#,
            #"(?i)\bcode\s*[:=]?\s*([45]\d{2})\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let codeRange = Range(match.range(at: 1), in: text),
                  let code = Int(text[codeRange]) else { continue }
            return code
        }
        return nil
    }

    private static func intValue(_ text: String?) -> Int? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }
}
