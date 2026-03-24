import Foundation

/// Claude model available via Claude Code CLI (`--model`)
public struct ClaudeModel: Sendable {
    public let slug: String
    public let displayName: String
    public let shortName: String

    public init(slug: String, displayName: String, shortName: String) {
        self.slug = slug
        self.displayName = displayName
        self.shortName = shortName
    }
}

/// Static list of Claude models available via Claude Code CLI.
/// Claude CLI has no `models list` command; models are known from documentation.
/// The slug is passed directly to the `--model` flag.
public enum ClaudeModelsCache {
    private static let knownModels: [ClaudeModel] = [
        // Claude 4.6
        ClaudeModel(slug: "claude-opus-4-6[1m]", displayName: "Opus 4.6 (1M)", shortName: "opus-1m"),
        ClaudeModel(slug: "claude-opus-4-6", displayName: "Opus 4.6", shortName: "opus"),
        ClaudeModel(slug: "claude-sonnet-4-6", displayName: "Sonnet 4.6", shortName: "sonnet"),
        // Claude 4
        ClaudeModel(slug: "claude-opus-4", displayName: "Opus 4", shortName: "opus"),
        ClaudeModel(slug: "claude-sonnet-4", displayName: "Sonnet 4", shortName: "sonnet"),
        // Claude 4.5
        ClaudeModel(
            slug: "claude-haiku-4-5-20251001", displayName: "Haiku 4.5", shortName: "haiku"),
    ]

    /// Returns the list of available Claude models.
    public static func loadModels() -> [ClaudeModel] {
        knownModels
    }

    /// Finds the displayName for a slug or shortName. Returns the slug itself if not found.
    public static func displayName(for modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let model = knownModels.first(where: { $0.slug == trimmed }) {
            return model.displayName
        }
        // Fallback: match by short name (legacy compatibility)
        if let model = knownModels.first(where: { $0.shortName == trimmed.lowercased() }) {
            return model.displayName
        }
        return trimmed.isEmpty ? "Default" : trimmed
    }
}
