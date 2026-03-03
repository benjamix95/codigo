import Foundation

// MARK: - Error Types

public enum WebToolsError: LocalizedError, Sendable {
    case invalidURL(String)
    case httpError(Int)
    case decodingFailed
    case searchFailed(String)
    case timeout
    case noResults

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingFailed: return "Failed to decode page content"
        case .searchFailed(let msg): return "Search failed: \(msg)"
        case .timeout: return "Request timed out"
        case .noResults: return "No results found"
        }
    }
}

// MARK: - Search Provider

/// Available web search providers.
public enum WebSearchProvider: String, CaseIterable, Sendable {
    case duckduckgo = "duckduckgo"
    case brave = "brave"
    case tavily = "tavily"
    case serper = "serper"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .tavily: return "Tavily"
        case .serper: return "Serper"
        }
    }

    /// Whether this provider requires an API key to function.
    public var requiresApiKey: Bool {
        switch self {
        case .duckduckgo: return false
        case .brave, .tavily, .serper: return true
        }
    }

    /// Signup URL where users can obtain an API key.
    public var signupURL: String {
        switch self {
        case .duckduckgo: return ""
        case .brave: return "https://brave.com/search/api/"
        case .tavily: return "https://tavily.com"
        case .serper: return "https://serper.dev"
        }
    }

    /// Short description of the free tier.
    public var freeTierDescription: String {
        switch self {
        case .duckduckgo: return "Free, unlimited, no API key needed"
        case .brave: return "Free tier: 2,000 queries/month"
        case .tavily: return "Free tier: 1,000 queries/month"
        case .serper: return "Free tier: 2,500 queries/month"
        }
    }
}

// MARK: - Search Models

public struct WebSearchResult: Sendable {
    public let title: String
    public let snippet: String
    public let url: String
}
