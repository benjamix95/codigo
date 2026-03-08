import Foundation

extension ClaudeCLIProvider {
    func runStreamingRequest(
        path: String,
        workspacePath: URL,
        fullPrompt: String,
        model: String?,
        allowedTools: [String],
        environmentOverride: [String: String]?,
        executionController: ExecutionController?,
        executionScope: ExecutionScope,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            continuation.yield(.error("Claude CLI not found at \(path). Install it from https://claude.com/code"))
            throw CoderEngineError.cliNotFound("claude")
        }

        let args = Self.buildCLIArguments(
            fullPrompt: fullPrompt,
            model: model,
            allowedTools: allowedTools
        )
        let stream = try await ProcessRunner.run(
            executable: path,
            arguments: args,
            workingDirectory: workspacePath,
            environment: Self.mergedEnvironment(with: environmentOverride),
            executionController: executionController,
            scope: executionScope
        )

        continuation.yield(.started)
        var fullContent = ""
        var accumulatedThinking = ""
        var lastUsageSignature = ""

        for try await line in stream {
            guard let data = line.data(using: String.Encoding.utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let usagePayload = Self.extractUsagePayload(from: json, defaultModel: model) {
                let signature = [
                    usagePayload["model"] ?? "claude",
                    usagePayload["input_tokens"] ?? "0",
                    usagePayload["output_tokens"] ?? "0",
                ].joined(separator: "|")
                if signature != lastUsageSignature {
                    lastUsageSignature = signature
                    continuation.yield(.raw(type: "usage", payload: usagePayload))
                }
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
                        "title": "Reasoning",
                        "group_id": "reasoning-stream",
                    ]))
                }
                if (delta["type"] as? String) == "text_delta",
                   let text = delta["text"] as? String {
                    fullContent += text
                    continuation.yield(.textDelta(text))
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
                            "title": "Reasoning",
                            "group_id": "reasoning-stream",
                        ]))
                    }
                    if (block["type"] as? String) == "text", let text = block["text"] as? String, !text.isEmpty {
                        if !fullContent.hasSuffix(text) {
                            let newLen = fullContent.count
                            fullContent += text
                            let delta = String(fullContent.dropFirst(newLen))
                            if !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
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
            }
        }

        continuation.yield(.completed)
    }
}
