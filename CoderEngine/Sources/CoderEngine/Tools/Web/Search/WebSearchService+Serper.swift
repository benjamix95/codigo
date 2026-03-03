import Foundation

extension WebSearchService {
    // MARK: Serper (Google) Search API

    func serperSearch(query: String, key: String, maxResults: Int) async throws -> [WebSearchResult] {
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
}
