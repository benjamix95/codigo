import Foundation

public extension GeminiCLIProvider {
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemBlock = context.systemPromptOverride ?? context.resolvedStandardAgentSystemPrompt
        let fullPrompt = systemBlock + "\n\n" + prompt + context.contextPrompt()
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

                    let env = self.shellEnvironment()

                    var args: [String]
                    if let model = self.modelOverride, !model.isEmpty {
                        args = ["-m", model, "-p", fullPrompt, "--output-format", "json"]
                    } else {
                        args = ["-p", fullPrompt, "--output-format", "json"]
                    }

                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: args,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: self.executionController,
                        scope: self.executionScope
                    )

                    continuation.yield(.started)
                    var fullText = ""
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
}
