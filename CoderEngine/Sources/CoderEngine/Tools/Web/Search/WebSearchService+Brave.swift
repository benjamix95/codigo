import Foundation

extension WebSearchService {
    // MARK: Brave Search API

    func braveSearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
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
}
