import Foundation

/// OpenAI client for one-shot calls (non-streaming completions)
public struct OpenAICompletionsClient: Sendable {
    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    /// Message for Chat Completions API
    public struct Message: Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }

        public static func system(_ content: String) -> Message {
            Message(role: "system", content: content)
        }

        public static func user(_ content: String) -> Message {
            Message(role: "user", content: content)
        }
    }

    /// Executes a one-shot completion and returns the response content
    public func complete(messages: [Message]) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CoderEngineError.apiError("OpenAI API error: invalid response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CoderEngineError.apiError("OpenAI API: failed to parse response")
        }

        return content
    }
}
