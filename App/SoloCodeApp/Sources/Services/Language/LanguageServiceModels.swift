import Foundation

enum LanguageServiceSource: String, Codable, Sendable {
    case sourceKitLSP = "sourcekit_lsp"
    case localIndex = "local_index"
}

struct LanguageLocation: Codable, Hashable, Sendable {
    let filePath: String
    let line: Int
    let column: Int?
    let symbolName: String
    let source: LanguageServiceSource
}

struct LanguageHoverResult: Codable, Sendable {
    let contents: String
    let source: LanguageServiceSource
}

struct LanguageRenamePlan: Codable, Sendable {
    let oldName: String
    let newName: String
    let references: [LanguageLocation]
    let source: LanguageServiceSource
}

struct LanguageServiceConfiguration: Sendable {
    let languageServiceEnabled: Bool
    let sourceKitLSPEnabled: Bool
    let sourceKitLSPPath: String

    static func load(from defaults: UserDefaults = .standard) -> LanguageServiceConfiguration {
        let languageEnabled = defaults.object(forKey: "language_service_enabled") as? Bool ?? true
        let sourcekitEnabled = defaults.object(forKey: "language_sourcekit_lsp_enabled") as? Bool ?? true
        let sourcekitPath = defaults.string(forKey: "language_sourcekit_lsp_path")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LanguageServiceConfiguration(
            languageServiceEnabled: languageEnabled,
            sourceKitLSPEnabled: sourcekitEnabled,
            sourceKitLSPPath: (sourcekitPath?.isEmpty == false ? sourcekitPath : nil) ?? "sourcekit-lsp"
        )
    }
}
