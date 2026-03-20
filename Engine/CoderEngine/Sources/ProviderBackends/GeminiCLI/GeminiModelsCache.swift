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

/// Static list of Gemini models available via Gemini CLI.
/// There is no `gemini models list` command; official documentation lists
/// Auto (Gemini 3), Auto (Gemini 2.5), or Manual with any available model.
/// This cache exposes the most common models for manual selection.
public enum GeminiModelsCache {
    /// Static models based on Gemini CLI documentation (geminicli.com/docs/cli/model).
    /// For "Default (auto)" don't pass --model: use geminiModelOverride = "".
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

    /// Returns the list of available models. An empty slug represents "Default (auto)".
    public static func loadModels() -> [GeminiModel] {
        knownModels
    }
}
