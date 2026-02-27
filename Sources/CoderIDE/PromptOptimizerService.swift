import CoderEngine
import Foundation

/// Servizio che usa il provider AI selezionato per ottimizzare un prompt utente.
/// Il prompt ottimizzato viene restituito nella stessa lingua dell'input.
@MainActor
final class PromptOptimizerService {

    enum OptimizeError: LocalizedError {
        case emptyPrompt
        case noProvider
        case emptyResponse
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case .emptyPrompt: return "Il prompt è vuoto."
            case .noProvider: return "Nessun provider AI selezionato."
            case .emptyResponse: return "Il provider ha restituito una risposta vuota."
            case .streamError(let msg): return msg
            }
        }
    }

    /// System prompt per l'ottimizzazione.
    private static let systemInstruction = """
    You are an expert at optimizing prompts for AI coding assistants.

    Rules:
    - Output ONLY the optimized prompt, no explanations.
    - Keep the same language as the input prompt.
    - Preserve intent, make it clearer and actionable.
    - Keep it concise and avoid unnecessary changes.
    """

    private static let cacheLimit = 64
    private static let cacheVersion = "v3"
    private static var promptCache: [String: String] = [:]
    private static var cacheOrder: [String] = []
    private static var inFlight: [String: Task<String, Error>] = [:]

    /// Ottimizza il prompt usando il provider fornito.
    /// Restituisce il testo ottimizzato.
    static func optimize(
        prompt: String,
        using provider: any LLMProvider,
        context: WorkspaceContext
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OptimizeError.emptyPrompt }

        let contextSignature = context.workspacePaths.map(\.path).joined(separator: "|")
        let cacheKey = "\(Self.cacheVersion)|\(provider.id)|\(contextSignature)|\(trimmed)"
        if let cached = promptCache[cacheKey] {
            return cached
        }
        if let running = inFlight[cacheKey] {
            return try await running.value
        }

        let fullPrompt = "\(systemInstruction)\n\nUSER:\n\(trimmed)"
        let task = Task<String, Error> {
            let stream = try await provider.send(
                prompt: fullPrompt,
                context: context,
                imageURLs: nil
            )

            var chunks: [String] = []
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    chunks.append(delta)
                case .error(let msg):
                    throw OptimizeError.streamError(msg)
                case .started, .completed, .raw:
                    break
                }
            }

            let optimized = chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !optimized.isEmpty else { throw OptimizeError.emptyResponse }
            return optimized
        }
        inFlight[cacheKey] = task
        defer { inFlight.removeValue(forKey: cacheKey) }

        let optimized = try await task.value
        if let existingIndex = cacheOrder.firstIndex(of: cacheKey) {
            cacheOrder.remove(at: existingIndex)
        }
        cacheOrder.append(cacheKey)
        promptCache[cacheKey] = optimized
        if cacheOrder.count > cacheLimit {
            let removeCount = cacheOrder.count - cacheLimit
            let removed = cacheOrder.prefix(removeCount)
            cacheOrder.removeFirst(removeCount)
            for key in removed {
                promptCache.removeValue(forKey: key)
            }
        }

        return optimized
    }
}
