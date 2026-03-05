import Foundation

struct OpenRouterModelCatalogSnapshot: Sendable {
    let allModels: [String]
    let freeModels: [String]

    static var fallback: OpenRouterModelCatalogSnapshot {
        let all = Set(openRouterPopularModels + openRouterFreeModels)
        return OpenRouterModelCatalogSnapshot(
            allModels: all.sorted(by: OpenRouterModelCatalogService.modelSort),
            freeModels: openRouterFreeModels
        )
    }
}

actor OpenRouterModelCatalogService {
    static let shared = OpenRouterModelCatalogService()

    private let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private let cacheTTL: TimeInterval = 60 * 30
    private var cachedSnapshot: OpenRouterModelCatalogSnapshot?
    private var cachedAt: Date?

    func fetchCatalog(forceRefresh: Bool = false) async -> OpenRouterModelCatalogSnapshot {
        if !forceRefresh,
           let cachedSnapshot,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < cacheTTL {
            return cachedSnapshot
        }

        do {
            let remote = try await fetchRemoteCatalog()
            cachedSnapshot = remote
            cachedAt = Date()
            return remote
        } catch {
            return cachedSnapshot ?? .fallback
        }
    }

    private func fetchRemoteCatalog() async throws -> OpenRouterModelCatalogSnapshot {
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode) else {
            throw OpenRouterCatalogError.badStatusCode
        }

        let payload = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        let allModels = Set(payload.data.map(\.id).filter { !$0.isEmpty })
            .sorted(by: Self.modelSort)
        let freeModels = Set(payload.data.filter(Self.isFreeModel).map(\.id))
            .sorted(by: Self.modelSort)

        return OpenRouterModelCatalogSnapshot(allModels: allModels, freeModels: freeModels)
    }

    private static func isFreeModel(_ model: OpenRouterRemoteModel) -> Bool {
        guard let pricing = model.pricing else { return false }
        let prompt = decimalValue(from: pricing.prompt)
        let completion = decimalValue(from: pricing.completion) ?? 0
        guard let prompt else { return false }
        return prompt == 0 && completion == 0
    }

    private static func decimalValue(from raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func modelSort(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterRemoteModel]
}

private struct OpenRouterRemoteModel: Decodable {
    let id: String
    let pricing: OpenRouterPricing?
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?
}

private enum OpenRouterCatalogError: Error {
    case badStatusCode
}
