import Foundation

/// Provider Anthropic Messages API con streaming SSE.
public final class AnthropicAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String

    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 4096,
        id: String = "anthropic-api",
        displayName: String = "Anthropic"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.id = id
        self.displayName = displayName
    }

    public func isAuthenticated() -> Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let fullPrompt = prompt + context.contextPrompt()
        let apiKey = self.apiKey
        let model = self.model
        let maxTokens = self.maxTokens

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                        throw CoderEngineError.apiError("Anthropic API URL non valida")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "accept")

                    var content: [[String: Any]] = []
                    if let urls = imageURLs, !urls.isEmpty {
                        for imgURL in urls {
                            if let data = try? Data(contentsOf: imgURL),
                               let ext = imgURL.pathExtension.lowercased() as String?,
                               let mediaType = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg") {
                                let b64 = data.base64EncodedString()
                                content.append([
                                    "type": "image",
                                    "source": ["type": "base64", "media_type": mediaType, "data": b64]
                                ])
                            }
                        }
                    }
                    content.append(["type": "text", "text": fullPrompt])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "messages": [
                            [
                                "role": "user",
                                "content": content
                            ]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CoderEngineError.apiError("Anthropic API response non valida")
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw CoderEngineError.apiError("Anthropic API HTTP \(httpResponse.statusCode)")
                    }

                    continuation.yield(.started)

                    var lastUsage: (Int, Int)?
                    var buffer = [UInt8]()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte != 10 { continue } // newline

                        let line = String(bytes: buffer, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        buffer.removeAll()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else {
                            continue
                        }

                        switch type {
                        case "content_block_delta":
                            guard let delta = json["delta"] as? [String: Any],
                                  (delta["type"] as? String) == "text_delta",
                                  let text = delta["text"] as? String,
                                  !text.isEmpty else { continue }
                            continuation.yield(.textDelta(text))
                        case "message_delta":
                            if let usage = json["usage"] as? [String: Any],
                               let inp = usage["input_tokens"] as? Int,
                               let out = usage["output_tokens"] as? Int {
                                lastUsage = (inp, out)
                            }
                        case "message_stop":
                            if let (inp, out) = lastUsage {
                                continuation.yield(.raw(type: "usage", payload: [
                                    "input_tokens": "\(inp)",
                                    "output_tokens": "\(out)",
                                    "model": model
                                ]))
                            }
                        case "error":
                            let errorPayload = json["error"] as? [String: Any]
                            let message = errorPayload?["message"] as? String ?? "Anthropic API error"
                            continuation.yield(.error(message))
                        default:
                            continue
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
