import Foundation

/// OpenAI-compatible API provider (usable for OpenAI, OpenRouter, MiniMax, and others).
public final class OpenAIAPIProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )

    let apiKey: String
    let model: String
    let reasoningEffort: String?
    let baseURL: String
    let extraHeaders: [String: String]
    let maxRetries: Int
    let timeoutSeconds: TimeInterval
    let initialRetryDelaySeconds: TimeInterval
    let maxRetryDelaySeconds: TimeInterval

    /// Models that support reasoning effort: o1, o3, o4-mini.
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
        extraHeaders: [String: String] = [:],
        maxRetries: Int = 3,
        timeoutSeconds: TimeInterval = 60,
        initialRetryDelaySeconds: TimeInterval = 0.5,
        maxRetryDelaySeconds: TimeInterval = 8
    ) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.extraHeaders = extraHeaders
        self.maxRetries = max(1, maxRetries)
        self.timeoutSeconds = max(10, timeoutSeconds)
        self.initialRetryDelaySeconds = max(0.1, initialRetryDelaySeconds)
        self.maxRetryDelaySeconds = max(self.initialRetryDelaySeconds, maxRetryDelaySeconds)
    }

    public func isAuthenticated() -> Bool {
        !apiKey.isEmpty
    }

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
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

/// CoderEngine errors.
public enum CoderEngineError: Error, Sendable {
    case notAuthenticated
    case apiError(String)
    case cliNotFound(String)
}

extension CoderEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Provider is not authenticated"
        case .apiError(let message):
            return message
        case .cliNotFound(let path):
            return "CLI not found: \(path)"
        }
    }
}
