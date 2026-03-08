import Foundation

/// Performs real web searches using the configured provider.
/// Supports DuckDuckGo (free default), Brave Search, Tavily, and Serper.
public actor WebSearchService {
    let provider: WebSearchProvider
    let apiKeys: [WebSearchProvider: String]
    let searchTimeoutSeconds: TimeInterval = 15

    /// Initialize with a specific provider and per-provider API keys.
    /// - Parameters:
    ///   - provider: The search provider to use (default: `.duckduckgo`).
    ///   - apiKeys: A map of provider → API key. Only needed for providers that require keys.
    public init(provider: WebSearchProvider = .duckduckgo, apiKeys: [WebSearchProvider: String] = [:]) {
        self.provider = provider
        self.apiKeys = apiKeys
    }

    /// Legacy convenience initializer for backward compatibility.
    public init(apiKey: String?) {
        if let key = apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.provider = .brave
            self.apiKeys = [.brave: key]
        } else {
            self.provider = .duckduckgo
            self.apiKeys = [:]
        }
    }

    /// The currently active search provider.
    public var activeProvider: WebSearchProvider { provider }

    /// Search the web and return structured results.
    public func search(query: String, maxResults: Int = 10) async throws -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WebToolsError.searchFailed("Empty query")
        }

        switch provider {
        case .duckduckgo:
            return try await duckDuckGoSearch(query: trimmed, maxResults: maxResults)
        case .brave:
            guard let key = validKey(for: .brave) else {
                // Fallback to DuckDuckGo if Brave key is missing
                return try await duckDuckGoSearch(query: trimmed, maxResults: maxResults)
            }
            return try await braveSearch(query: trimmed, key: key, maxResults: maxResults)
        case .tavily:
            guard let key = validKey(for: .tavily) else {
                return try await duckDuckGoSearch(query: trimmed, maxResults: maxResults)
            }
            return try await tavilySearch(query: trimmed, key: key, maxResults: maxResults)
        case .serper:
            guard let key = validKey(for: .serper) else {
                return try await duckDuckGoSearch(query: trimmed, maxResults: maxResults)
            }
            return try await serperSearch(query: trimmed, key: key, maxResults: maxResults)
        }
    }

    /// Returns a non-empty API key for the given provider, or nil.
    func validKey(for provider: WebSearchProvider) -> String? {
        guard let key = apiKeys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }
}
