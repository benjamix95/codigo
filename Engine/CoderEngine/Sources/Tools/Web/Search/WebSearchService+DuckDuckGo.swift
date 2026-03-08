import Foundation

extension WebSearchService {
    // MARK: DuckDuckGo HTML Fallback

    func duckDuckGoSearch(query: String, maxResults: Int) async throws -> [WebSearchResult] {
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
    func parseDuckDuckGoHTML(_ html: String, maxResults: Int) -> [WebSearchResult] {
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
}
