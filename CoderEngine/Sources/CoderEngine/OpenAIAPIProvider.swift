import Foundation

/// Provider OpenAI-compatible via API diretta (usabile per OpenAI, OpenRouter, MiniMax, ecc.)
public final class OpenAIAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    
    private let apiKey: String
    private let model: String
    private let reasoningEffort: String?
    private let baseURL: String
    private let extraHeaders: [String: String]
    
    /// Modelli che supportano reasoning effort: o1, o3, o4-mini
    public static func isReasoningModel(_ name: String) -> Bool {
        name.hasPrefix("o1") || name.hasPrefix("o3") || name.hasPrefix("o4")
    }
    
    public init(
        apiKey: String,
        model: String = "gpt-4o-mini",
        reasoningEffort: String? = nil,
        id: String = "openai-api",
        displayName: String = "OpenAI API",
        baseURL: String = "https://api.openai.com/v1/chat/completions",
        extraHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.extraHeaders = extraHeaders
    }
    
    public func isAuthenticated() -> Bool {
        !apiKey.isEmpty
    }

    private static func supportsStreamUsage(baseURL: String) -> Bool {
        let lower = baseURL.lowercased()
        return lower.contains("/chat/completions")
    }

    private static func extractUsage(from json: [String: Any]) -> (Int, Int)? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int)
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int)
        guard let input, let output else { return nil }
        return (input, output)
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        let baseURL = self.baseURL
        let extraHeaders = self.extraHeaders
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: baseURL)!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (key, value) in extraHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    var content: Any
                    if let urls = imageURLs, !urls.isEmpty {
                        var items: [[String: Any]] = []
                        for imgURL in urls {
                            if let data = try? Data(contentsOf: imgURL) {
                                let ext = imgURL.pathExtension.lowercased()
                                let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                                let b64 = data.base64EncodedString()
                                items.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:\(mime);base64,\(b64)"]
                                ])
                            }
                        }
                        if !items.isEmpty {
                            items.insert(["type": "text", "text": fullPrompt], at: 0)
                            content = items
                        } else {
                            content = fullPrompt
                        }
                    } else {
                        content = fullPrompt
                    }
                    
                    var body: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "user", "content": content]
                        ],
                        "stream": true
                    ]
                    if Self.supportsStreamUsage(baseURL: baseURL) {
                        body["stream_options"] = ["include_usage": true]
                    }
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
                    var didEmitUsage = false
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 10 { // newline
                            let line = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            buffer.removeAll()
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst(6))
                            if jsonStr == "[DONE]" {
                                if !didEmitUsage {
                                    continuation.yield(.raw(type: "usage", payload: [
                                        "input_tokens": "-1",
                                        "output_tokens": "-1",
                                        "model": model
                                    ]))
                                }
                                continuation.yield(.completed)
                                continuation.finish()
                                return
                            }
                            guard let lineData = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                                continue
                            }
                            if let (inp, out) = Self.extractUsage(from: json) {
                                continuation.yield(.raw(type: "usage", payload: [
                                    "input_tokens": "\(inp)",
                                    "output_tokens": "\(out)",
                                    "model": model
                                ]))
                                didEmitUsage = true
                            }
                            guard let choices = json["choices"] as? [[String: Any]],
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
