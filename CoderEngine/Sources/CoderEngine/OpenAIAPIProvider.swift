import Foundation

/// Provider OpenAI via API diretta
public final class OpenAIAPIProvider: LLMProvider, @unchecked Sendable {
    public let id = "openai-api"
    public let displayName = "OpenAI API"
    
    private let apiKey: String
    private let model: String
    private let reasoningEffort: String?
    
    /// Modelli che supportano reasoning effort: o1, o3, o4-mini
    public static func isReasoningModel(_ name: String) -> Bool {
        name.hasPrefix("o1") || name.hasPrefix("o3") || name.hasPrefix("o4")
    }
    
    public init(apiKey: String, model: String = "gpt-4o-mini", reasoningEffort: String? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
    
    public func isAuthenticated() -> Bool {
        !apiKey.isEmpty
    }
    
    public func send(prompt: String, context: WorkspaceContext) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    var body: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "user", "content": fullPrompt]
                        ],
                        "stream": true
                    ]
                    if Self.isReasoningModel(model), let effort = reasoningEffort {
                        body["reasoning"] = ["effort": effort]
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: CoderEngineError.apiError("Invalid response"))
                        return
                    }
                    
                    continuation.yield(.started)
                    
                    var buffer = [UInt8]()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 10 { // newline
                            let line = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            buffer.removeAll()
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst(6))
                            if jsonStr == "[DONE]" {
                                continuation.yield(.completed)
                                continuation.finish()
                                return
                            }
                            guard let lineData = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                                  let choices = json["choices"] as? [[String: Any]],
                                  let first = choices.first,
                                  let delta = first["delta"] as? [String: Any],
                                  let content = delta["content"] as? String,
                                  !content.isEmpty else {
                                continue
                            }
                            continuation.yield(.textDelta(content))
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
}

/// Errori CoderEngine
public enum CoderEngineError: Error, Sendable {
    case notAuthenticated
    case apiError(String)
    case cliNotFound(String)
}
