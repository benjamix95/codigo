import Foundation

/// Anthropic Messages API provider with SSE streaming.
public final class AnthropicAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )

    let apiKey: String
    let model: String
    let maxTokens: Int
    let maxRetries: Int
    let timeoutSeconds: TimeInterval
    let initialRetryDelaySeconds: TimeInterval
    let maxRetryDelaySeconds: TimeInterval

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 4096,
        id: String = "anthropic-api",
        displayName: String = "Anthropic",
        maxRetries: Int = 3,
        timeoutSeconds: TimeInterval = 60,
        initialRetryDelaySeconds: TimeInterval = 0.5,
        maxRetryDelaySeconds: TimeInterval = 8
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.id = id
        self.displayName = displayName
        self.maxRetries = max(1, maxRetries)
        self.timeoutSeconds = max(10, timeoutSeconds)
        self.initialRetryDelaySeconds = max(0.1, initialRetryDelaySeconds)
        self.maxRetryDelaySeconds = max(self.initialRetryDelaySeconds, maxRetryDelaySeconds)
    }

    public func isAuthenticated() -> Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func supportsExtendedThinking(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("opus-4") || m.contains("sonnet-4") || m.contains("haiku-4")
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        let fullPrompt = prompt + context.contextPrompt()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runStreamingRequest(
                        fullPrompt: fullPrompt,
                        context: context,
                        imageURLs: imageURLs,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}
