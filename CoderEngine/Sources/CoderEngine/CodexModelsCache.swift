import Foundation

/// Modello Codex recuperato dalla cache
public struct CodexModel: Sendable {
    public let slug: String
    public let displayName: String
    public let reasoningLevels: [String]
    
    public init(slug: String, displayName: String, reasoningLevels: [String]) {
        self.slug = slug
        self.displayName = displayName
        self.reasoningLevels = reasoningLevels
    }
}

/// Legge i modelli disponibili da ~/.codex/models_cache.json (popolato dal Codex CLI)
public enum CodexModelsCache {
    private static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }
    
    private static var modelsCachePath: String {
        "\(codexHome)/models_cache.json"
    }
    
    /// Recupera la lista dei modelli dalla cache. Ritorna vuoto se il file non esiste o non è valido.
    public static func loadModels() -> [CodexModel] {
        let path = modelsCachePath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else {
            return []
        }
        
        return modelsArray.compactMap { dict -> CodexModel? in
            guard let slug = dict["slug"] as? String else { return nil }
            let displayName = dict["display_name"] as? String ?? slug
            let reasoningLevels: [String] = (dict["supported_reasoning_levels"] as? [[String: Any]])?
                .compactMap { $0["effort"] as? String }
                .sorted { l, r in orderReasoningLevel(l) < orderReasoningLevel(r) }
                ?? ["low", "medium", "high", "xhigh"]
            return CodexModel(slug: slug, displayName: displayName, reasoningLevels: reasoningLevels)
        }
    }
    
    private static func orderReasoningLevel(_ s: String) -> Int {
        switch s.lowercased() {
        case "low": return 0
        case "medium": return 1
        case "high": return 2
        case "xhigh": return 3
        default: return 4
        }
    }
}
