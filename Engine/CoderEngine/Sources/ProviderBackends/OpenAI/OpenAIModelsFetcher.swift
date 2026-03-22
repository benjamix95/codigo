import Foundation

/// Fetches available models from the OpenAI API (`GET /v1/models`).
/// Includes a 5-minute in-memory cache to avoid excessive requests.
public enum OpenAIModelsFetcher {
    private static let lock = NSLock()
    private static var cachedModels: [String]?
    private static var cacheDate: Date?
    private static let cacheTTL: TimeInterval = 300 // 5 minuti

    /// Fallback statico in caso di errore di rete
    public static let fallbackModels = [
        "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
        "gpt-4o", "gpt-4o-mini",
        "o3", "o3-pro", "o4-mini",
        "o3-mini",
    ]

    /// Prefissi dei modelli da includere (chat-compatible)
    private static let allowedPrefixes = [
        "gpt-4", "gpt-3.5", "gpt-5",
        "o1", "o3", "o4",
        "chatgpt-",
    ]

    /// Suffissi da escludere (snapshot, audio, realtime, etc.)
    private static let excludedSuffixes = [
        "-audio-preview", "-realtime-preview",
        "-search-preview", "-transcribe", "-tts",
    ]

    /// Modelli esatti da escludere
    private static let excludedExact: Set<String> = [
        "gpt-4o-audio-preview",
        "gpt-4o-mini-audio-preview",
        "gpt-4o-realtime-preview",
        "gpt-4o-mini-realtime-preview",
        "gpt-4o-mini-search-preview",
        "gpt-4o-search-preview",
    ]

    /// Fetches models from the OpenAI API, filtered and sorted.
    /// Returns cached results if available within TTL.
    public static func fetchModels(apiKey: String) async -> [String] {
        let cached: [String]? = lock.withLock {
            if let c = cachedModels,
               let d = cacheDate,
               Date().timeIntervalSince(d) < cacheTTL { return c }
            return nil
        }
        if let cached { return cached }

        guard !apiKey.isEmpty else { return fallbackModels }

        do {
            let models = try await performFetch(apiKey: apiKey)
            let filtered = filterAndSort(models)
            lock.withLock {
                cachedModels = filtered
                cacheDate = Date()
            }
            return filtered
        } catch {
            return fallbackModels
        }
    }

    /// Invalida la cache per forzare un nuovo fetch
    public static func invalidateCache() {
        lock.withLock {
            cachedModels = nil
            cacheDate = nil
        }
    }

    // MARK: - Private

    private static func performFetch(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return fallbackModels
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return fallbackModels
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return fallbackModels
        }

        return dataArray.compactMap { $0["id"] as? String }
    }

    private static func filterAndSort(_ models: [String]) -> [String] {
        let filtered = models.filter { model in
            let lower = model.lowercased()
            // Deve iniziare con un prefisso consentito
            guard allowedPrefixes.contains(where: { lower.hasPrefix($0) }) else {
                return false
            }
            // Non deve avere un suffisso escluso
            if excludedSuffixes.contains(where: { lower.hasSuffix($0) }) {
                return false
            }
            // Non deve essere un modello esatto escluso
            if excludedExact.contains(lower) {
                return false
            }
            // Escludi snapshot con date (es. gpt-4o-2024-05-13)
            if lower.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
                return false
            }
            return true
        }

        // Ordina: reasoning models (o*) prima, poi gpt-5, gpt-4.1, gpt-4o, etc.
        return filtered.sorted { a, b in
            let scoreA = modelSortScore(a)
            let scoreB = modelSortScore(b)
            if scoreA != scoreB { return scoreA < scoreB }
            return a < b
        }
    }

    private static func modelSortScore(_ model: String) -> Int {
        let lower = model.lowercased()
        if lower.hasPrefix("o3-pro") { return 0 }
        if lower.hasPrefix("o3") && !lower.hasPrefix("o3-mini") { return 1 }
        if lower.hasPrefix("o4-mini") { return 2 }
        if lower.hasPrefix("o3-mini") { return 3 }
        if lower.hasPrefix("o1") { return 4 }
        if lower.hasPrefix("gpt-5") { return 5 }
        if lower.hasPrefix("gpt-4.1") && !lower.contains("mini") && !lower.contains("nano") { return 6 }
        if lower.hasPrefix("gpt-4.1-mini") { return 7 }
        if lower.hasPrefix("gpt-4.1-nano") { return 8 }
        if lower.hasPrefix("gpt-4o") && !lower.contains("mini") { return 9 }
        if lower.hasPrefix("gpt-4o-mini") { return 10 }
        if lower.hasPrefix("chatgpt") { return 11 }
        return 20
    }
}
