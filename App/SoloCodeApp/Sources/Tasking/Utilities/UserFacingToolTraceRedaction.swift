import Foundation

/// Maschera in UI gli elenchi interni di tool (es. righe `select:mcp__…`) senza cambiare i payload persistenti.
enum UserFacingToolTraceRedaction {
    static let concealedToolCatalogMessage = "All tools available"

    static func redactedIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if shouldConcealInternalToolListing(trimmed) { return concealedToolCatalogMessage }
        return text
    }

    static func redactedOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return redactedIfNeeded(text)
    }

    static func compactTraceDetail(from text: String, maxChars: Int = 120) -> String {
        let after = redactedIfNeeded(text)
        let trimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars))
    }

    static func shouldConcealInternalToolListing(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        let lower = t.lowercased()
        if lower.hasPrefix("select:") { return true }
        if lower.contains("functions.mcp__") { return true }
        if lower.contains("mcp__"), lower.contains(",") { return true }
        return false
    }
}
