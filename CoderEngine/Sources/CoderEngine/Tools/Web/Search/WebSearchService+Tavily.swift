import Foundation

extension WebSearchService {
    // MARK: Tavily Search API

    func tavilySearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
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
}
