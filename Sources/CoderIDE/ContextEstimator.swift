import Foundation
import CoderEngine

/// Stima token per messaggi + context (heuristica chars/4)
enum ContextEstimator {
    private static let charsPerToken = 4.0
    private static let systemPromptTokens = 500

    static func estimate(
        messages: [ChatMessage],
        contextPrompt: String,
        modelContextSize: Int = 128_000
    ) -> (estimatedTokens: Int, contextSize: Int, percentUsed: Double) {
        var totalChars = contextPrompt.count
        for msg in messages {
            totalChars += msg.content.count
            if let paths = msg.imagePaths, !paths.isEmpty {
                totalChars += paths.count * 500
            }
        }
        totalChars += systemPromptTokens * Int(charsPerToken)
        let estimated = Int(Double(totalChars) / charsPerToken) + systemPromptTokens
        let pct = min(1.0, Double(estimated) / Double(modelContextSize))
        return (estimated, modelContextSize, pct)
    }

    static func contextSize(for providerId: String?, model: String?) -> Int {
        if let m = model, !m.isEmpty {
            return ModelPricing.contextWindowSize(for: m)
        }
        let id = (providerId ?? "").lowercased()
        if id.contains("claude") { return 200_000 }
        if id.contains("codex") { return 200_000 }
        return 128_000
    }
}
