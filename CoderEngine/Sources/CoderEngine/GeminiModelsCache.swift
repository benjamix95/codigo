import Foundation

/// Modello Gemini compatibile con Gemini CLI (`--model`)
public struct GeminiModel: Sendable {
    public let slug: String
    public let displayName: String

    public init(slug: String, displayName: String) {
        self.slug = slug
        self.displayName = displayName
    }
}

/// Lista statica dei modelli Gemini disponibili via Gemini CLI.
/// Non esiste un comando `gemini models list`; la documentazione ufficiale indica
/// Auto (Gemini 3), Auto (Gemini 2.5), oppure Manual con qualsiasi modello disponibile.
/// Questa cache espone i modelli più comuni per la selezione manuale.
public enum GeminiModelsCache {
    /// Modelli statici basati sulla documentazione Gemini CLI (geminicli.com/docs/cli/model).
    /// Per "Default (auto)" non passare --model: usare geminiModelOverride = "".
    private static let knownModels: [GeminiModel] = [
        // Gemini 3 (preview)
        GeminiModel(slug: "gemini-3-pro-preview", displayName: "Gemini 3 Pro (preview)"),
        GeminiModel(slug: "gemini-3-flash-preview", displayName: "Gemini 3 Flash (preview)"),
        // Gemini 2.5
        GeminiModel(slug: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
        GeminiModel(slug: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        GeminiModel(slug: "gemini-2.5-flash-preview-05-20", displayName: "Gemini 2.5 Flash Preview"),
        // Gemini 2.0
        GeminiModel(slug: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash"),
        GeminiModel(slug: "gemini-2.0-flash-exp", displayName: "Gemini 2.0 Flash Exp"),
    ]

    /// Restituisce la lista dei modelli disponibili. Lo slug vuoto rappresenta "Default (auto)".
    public static func loadModels() -> [GeminiModel] {
        knownModels
    }
}
