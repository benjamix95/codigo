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

// MARK: - Web Search

public struct WebSearchResult: Sendable {
    public let title: String
    public let snippet: String
    public let url: String
}

/// Performs real web searches using the configured provider.
/// Supports DuckDuckGo (free default), Brave Search, Tavily, and Serper.
public actor WebSearchService {
    private let provider: WebSearchProvider
    private let apiKeys: [WebSearchProvider: String]
    private let searchTimeoutSeconds: TimeInterval = 15

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
    private func validKey(for provider: WebSearchProvider) -> String? {
        guard let key = apiKeys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    // MARK: Brave Search API

    private func braveSearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search") else {
            throw WebToolsError.searchFailed("Failed to build Brave Search URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(min(maxResults, 20))"),
        ]
        guard let url = components.url else {
            throw WebToolsError.searchFailed("Failed to build Brave Search URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CoderIDE/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = searchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = searchTimeoutSeconds
        config.timeoutIntervalForResource = searchTimeoutSeconds + 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebToolsError.searchFailed("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebToolsError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            throw WebToolsError.searchFailed("Unexpected Brave Search response format")
        }

        return results.prefix(maxResults).compactMap { item -> WebSearchResult? in
            guard let title = item["title"] as? String,
                  let url = item["url"] as? String else { return nil }
            let snippet = (item["description"] as? String) ?? ""
            return WebSearchResult(title: title, snippet: snippet, url: url)
        }
    }

    // MARK: DuckDuckGo HTML Fallback

    private func duckDuckGoSearch(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else {
            throw WebToolsError.searchFailed("Failed to build DuckDuckGo URL")
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw WebToolsError.searchFailed("Failed to build DuckDuckGo URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = searchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = searchTimeoutSeconds
        config.timeoutIntervalForResource = searchTimeoutSeconds + 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WebToolsError.httpError(code)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw WebToolsError.decodingFailed
        }

        return parseDuckDuckGoHTML(html, maxResults: maxResults)
    }

    /// Parse DuckDuckGo HTML results page to extract search results.
    private func parseDuckDuckGoHTML(_ html: String, maxResults: Int) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // DuckDuckGo HTML results have links in <a class="result__a" href="...">Title</a>
        // and snippets in <a class="result__snippet" ...>Snippet</a>
        // We extract both patterns with regex.

        // Pattern 1: Extract result links — href from the uddg redirect
        let linkPattern = #"<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#

        let linkMatches = regexMatches(pattern: linkPattern, in: html)
        let snippetMatches = regexMatches(pattern: snippetPattern, in: html)

        for (i, linkMatch) in linkMatches.prefix(maxResults).enumerated() {
            guard linkMatch.count >= 3 else { continue }

            var rawURL = linkMatch[1]
            let rawTitle = HTMLToMarkdown.stripTags(linkMatch[2])

            // DuckDuckGo wraps URLs in a redirect: //duckduckgo.com/l/?uddg=<encoded_url>&rut=...
            if rawURL.contains("uddg=") {
                if let range = rawURL.range(of: "uddg=") {
                    let afterUddg = String(rawURL[range.upperBound...])
                    let encoded = afterUddg.split(separator: "&").first.map(String.init) ?? afterUddg
                    rawURL = encoded.removingPercentEncoding ?? encoded
                }
            }

            let snippet: String
            if i < snippetMatches.count, snippetMatches[i].count >= 2 {
                snippet = HTMLToMarkdown.stripTags(snippetMatches[i][1])
            } else {
                snippet = ""
            }

            guard !rawTitle.isEmpty, !rawURL.isEmpty else { continue }
            results.append(WebSearchResult(title: rawTitle, snippet: snippet, url: rawURL))
        }

        return results
    }

    // MARK: Tavily Search API

    private func tavilySearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw WebToolsError.searchFailed("Failed to build Tavily URL")
        }

        let body: [String: Any] = [
            "query": query,
            "max_results": min(maxResults, 20),
            "search_depth": "basic",
            "include_answer": false,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("CoderIDE/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = searchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = searchTimeoutSeconds
        config.timeoutIntervalForResource = searchTimeoutSeconds + 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebToolsError.searchFailed("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebToolsError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw WebToolsError.searchFailed("Unexpected Tavily response format")
        }

        return results.prefix(maxResults).compactMap { item -> WebSearchResult? in
            guard let title = item["title"] as? String,
                  let url = item["url"] as? String else { return nil }
            let snippet = (item["content"] as? String) ?? ""
            return WebSearchResult(title: title, snippet: snippet, url: url)
        }
    }

    // MARK: Serper (Google) Search API

    private func serperSearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://google.serper.dev/search") else {
            throw WebToolsError.searchFailed("Failed to build Serper URL")
        }

        let body: [String: Any] = [
            "q": query,
            "num": min(maxResults, 20),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-API-KEY")
        request.setValue("CoderIDE/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = searchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = searchTimeoutSeconds
        config.timeoutIntervalForResource = searchTimeoutSeconds + 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebToolsError.searchFailed("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebToolsError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let organic = json["organic"] as? [[String: Any]] else {
            throw WebToolsError.searchFailed("Unexpected Serper response format")
        }

        return organic.prefix(maxResults).compactMap { item -> WebSearchResult? in
            guard let title = item["title"] as? String,
                  let link = item["link"] as? String else { return nil }
            let snippet = (item["snippet"] as? String) ?? ""
            return WebSearchResult(title: title, snippet: snippet, url: link)
        }
    }

    private func regexMatches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { i -> String? in
                let range = match.range(at: i)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }
}

// MARK: - Web Fetch

/// Fetches a web page and converts its HTML content to clean Markdown.
public actor WebFetchService {
    private let maxContentBytes: Int = 131_072  // 128KB
    private let maxOutputChars: Int = 12_000
    private let fetchTimeoutSeconds: TimeInterval = 30

    public init() {}

    /// Fetch a URL and return its content as Markdown.
    public func fetch(urlString: String) async throws -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw WebToolsError.invalidURL(urlString)
        }

        // Prepend https:// if no protocol
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }

        guard let url = URL(string: normalized) else {
            throw WebToolsError.invalidURL(normalized)
        }

        // Block localhost / private IPs
        if let host = url.host?.lowercased() {
            if isBlockedHost(host) {
                throw WebToolsError.invalidURL("Cannot fetch localhost or private network addresses")
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = fetchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = fetchTimeoutSeconds
        config.timeoutIntervalForResource = fetchTimeoutSeconds + 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response, wasDownloadTruncated) = try await fetchDataWithLimit(
            session: session,
            request: request,
            maxBytes: maxContentBytes
        )
        guard let http = response as? HTTPURLResponse else {
            throw WebToolsError.searchFailed("Invalid HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebToolsError.httpError(http.statusCode)
        }

        // Detect content type — only process text/HTML
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isHTML = contentType.contains("text/html") || contentType.contains("application/xhtml")
        let isText = contentType.contains("text/") || contentType.contains("application/json") || contentType.contains("application/xml")

        guard isHTML || isText || contentType.isEmpty else {
            throw WebToolsError.decodingFailed
        }

        // Detect encoding from Content-Type header
        let encoding = detectEncoding(from: contentType) ?? .utf8
        guard let rawContent = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw WebToolsError.decodingFailed
        }

        // Convert HTML → Markdown (or return raw text for non-HTML)
        let markdown: String
        if isHTML || contentType.isEmpty {
            markdown = HTMLToMarkdown.convert(rawContent)
        } else {
            markdown = rawContent
        }

        var output = markdown
        var notes: [String] = []

        // Truncate output
        if output.count > maxOutputChars {
            output = String(output.prefix(maxOutputChars))
            notes.append("...[content truncated at \(maxOutputChars) chars]")
        }
        if wasDownloadTruncated {
            notes.append("...[download truncated at \(maxContentBytes) bytes]")
        }

        if !notes.isEmpty {
            output += "\n\n" + notes.joined(separator: "\n")
        }
        return output
    }

    private func detectEncoding(from contentType: String) -> String.Encoding? {
        let lower = contentType.lowercased()
        if lower.contains("charset=utf-8") { return .utf8 }
        if lower.contains("charset=iso-8859-1") || lower.contains("charset=latin1") { return .isoLatin1 }
        if lower.contains("charset=ascii") { return .ascii }
        if lower.contains("charset=windows-1252") { return .windowsCP1252 }
        return nil
    }

    private func fetchDataWithLimit(
        session: URLSession,
        request: URLRequest,
        maxBytes: Int
    ) async throws -> (Data, URLResponse, Bool) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }

        var collected = Data()
        collected.reserveCapacity(min(maxBytes, 32_768))

        var iterator = bytes.makeAsyncIterator()
        while let byte = try await iterator.next() {
            if collected.count >= maxBytes {
                return (collected, response, true)
            }
            collected.append(byte)
        }
        return (collected, response, false)
    }

    private func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "0.0.0.0" {
            return true
        }
        guard let ipv4 = parseIPv4(host) else {
            return false
        }
        let a = ipv4.0
        let b = ipv4.1

        if a == 10 { return true }                    // 10.0.0.0/8
        if a == 127 { return true }                   // 127.0.0.0/8 (loopback)
        if a == 192 && b == 168 { return true }      // 192.168.0.0/16
        if a == 172 && (16...31).contains(b) { return true }  // 172.16.0.0/12
        return false
    }

    private func parseIPv4(_ host: String) -> (Int, Int, Int, Int)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (octets[0], octets[1], octets[2], octets[3])
    }
}

// MARK: - HTML to Markdown Converter

/// Lightweight, zero-dependency HTML → Markdown converter.
/// Uses regex-based transformations for speed and simplicity.
public enum HTMLToMarkdown {

    /// Convert HTML string to clean Markdown.
    public static func convert(_ html: String) -> String {
        var text = html

        // 1. Remove entire blocks of non-content tags
        let blockTags = ["script", "style", "noscript", "svg", "iframe", "object", "embed", "applet", "form"]
        for tag in blockTags {
            text = replaceRegex(
                in: text,
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: ""
            )
        }

        // 2. Try to extract <article> or <main> content for readability
        text = extractMainContent(text)

        // 3. Remove <nav>, <footer>, <header>, <aside> blocks (after content extraction)
        let removeTags = ["nav", "footer", "aside"]
        for tag in removeTags {
            text = replaceRegex(in: text, pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: "")
        }

        // 4. Convert headings: <h1>...</h1> → # ...
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            text = replaceRegex(
                in: text,
                pattern: "<h\(level)[^>]*>(.*?)</h\(level)>",
                with: "\n\n\(prefix) $1\n\n"
            )
        }

        // 5. Convert links: <a href="url">text</a> → [text](url)
        text = replaceRegex(
            in: text,
            pattern: #"<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#,
            with: "[$2]($1)"
        )

        // 6. Convert emphasis
        text = replaceRegex(in: text, pattern: "<strong[^>]*>(.*?)</strong>", with: "**$1**")
        text = replaceRegex(in: text, pattern: "<b[^>]*>(.*?)</b>", with: "**$1**")
        text = replaceRegex(in: text, pattern: "<em[^>]*>(.*?)</em>", with: "*$1*")
        text = replaceRegex(in: text, pattern: "<i[^>]*>(.*?)</i>", with: "*$1*")

        // 7. Convert code
        text = replaceRegex(in: text, pattern: "<code[^>]*>(.*?)</code>", with: "`$1`")
        text = replaceRegex(
            in: text,
            pattern: "<pre[^>]*>(.*?)</pre>",
            with: "\n```\n$1\n```\n"
        )

        // 8. Convert lists
        text = replaceRegex(in: text, pattern: "<li[^>]*>(.*?)</li>", with: "\n- $1")
        text = replaceRegex(in: text, pattern: "</?[uo]l[^>]*>", with: "\n")

        // 9. Convert paragraphs and line breaks
        text = replaceRegex(in: text, pattern: "<br[^>]*/?>", with: "\n")
        text = replaceRegex(in: text, pattern: "<p[^>]*>", with: "\n\n")
        text = replaceRegex(in: text, pattern: "</p>", with: "\n\n")
        text = replaceRegex(in: text, pattern: "<div[^>]*>", with: "\n")
        text = replaceRegex(in: text, pattern: "</div>", with: "\n")

        // 10. Convert <hr> → ---
        text = replaceRegex(in: text, pattern: "<hr[^>]*/?>", with: "\n\n---\n\n")

        // 11. Convert blockquotes
        text = replaceRegex(in: text, pattern: "<blockquote[^>]*>(.*?)</blockquote>", with: "\n> $1\n")

        // 12. Convert tables (basic)
        text = replaceRegex(in: text, pattern: "<tr[^>]*>", with: "\n| ")
        text = replaceRegex(in: text, pattern: "</tr>", with: " |")
        text = replaceRegex(in: text, pattern: "<t[hd][^>]*>(.*?)</t[hd]>", with: "$1 | ")

        // 13. Strip all remaining HTML tags
        text = replaceRegex(in: text, pattern: "<[^>]+>", with: "")

        // 14. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 15. Collapse excessive whitespace
        text = replaceRegex(in: text, pattern: "[ \\t]+", with: " ")
        text = replaceRegex(in: text, pattern: "\\n[ \\t]+", with: "\n")
        text = replaceRegex(in: text, pattern: "\\n{3,}", with: "\n\n")

        // 16. Final trim
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Strip HTML tags from a string (used for cleaning search result titles/snippets).
    public static func stripTags(_ html: String) -> String {
        var text = replaceRegex(in: html, pattern: "<[^>]+>", with: "")
        text = decodeHTMLEntities(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Private Helpers

    /// Try to extract <article> or <main> content for better readability.
    /// Falls back to <body> if neither is found.
    private static func extractMainContent(_ html: String) -> String {
        // Try <article> first
        if let content = extractTag("article", from: html) {
            return content
        }
        // Try <main>
        if let content = extractTag("main", from: html) {
            return content
        }
        // Try <body>
        if let content = extractTag("body", from: html) {
            return content
        }
        return html
    }

    private static func extractTag(_ tag: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return nsHTML.substring(with: range)
    }

    private static func replaceRegex(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&laquo;", "«"),
            ("&raquo;", "»"),
            ("&bull;", "•"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
            ("&times;", "×"),
            ("&divide;", "÷"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#123; → character
        if let numericRegex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsResult = result as NSString
            let matches = numericRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let codeRange = match.range(at: 1)
                    if codeRange.location != NSNotFound,
                       let code = Int(nsResult.substring(with: codeRange)),
                       let scalar = Unicode.Scalar(code) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                    }
                }
            }
        }
        // Hex numeric entities: &#x1F4A9; → character
        if let hexRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let nsResult = result as NSString
            let matches = hexRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let hexRange = match.range(at: 1)
                    if hexRange.location != NSNotFound,
                       let code = UInt32(nsResult.substring(with: hexRange), radix: 16),
                       let scalar = Unicode.Scalar(code) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                    }
                }
            }
        }
        return result
    }
}
