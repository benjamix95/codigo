import Foundation

/// Provider che usa Gemini CLI (`gemini -p`)
public final class GeminiCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"

    private let geminiPath: String
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        geminiPath: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        self.geminiPath = geminiPath ?? PathFinder.find(executable: "gemini") ?? "/opt/homebrew/bin/gemini"
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public func isAuthenticated() -> Bool {
        guard FileManager.default.fileExists(atPath: geminiPath) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: geminiPath)
        process.arguments = ["--version"]
        var env = CodexDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        process.environment = env
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

                    var env = CodexDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }

                    let stream = try await ProcessRunner.run(
                        executable: path,
                        arguments: ["-p", fullPrompt, "--output-format", "json"],
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )

                    continuation.yield(.started)
                    var fullText = ""
                    for try await line in stream {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let usage = json["usage"] as? [String: Any] {
                                let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int) ?? -1
                                let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int) ?? -1
                                continuation.yield(.raw(type: "usage", payload: [
                                    "input_tokens": "\(input)",
                                    "output_tokens": "\(output)",
                                    "model": "gemini-cli"
                                ]))
                            }
                            if let text = json["text"] as? String, !text.isEmpty {
                                let delta = text.hasPrefix(fullText) ? String(text.dropFirst(fullText.count)) : text
                                fullText = text
                                continuation.yield(.textDelta(delta))
                                continue
                            }
                            if let result = json["result"] as? String, !result.isEmpty {
                                let delta = result.hasPrefix(fullText) ? String(result.dropFirst(fullText.count)) : result
                                fullText = result
                                continuation.yield(.textDelta(delta))
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
}
