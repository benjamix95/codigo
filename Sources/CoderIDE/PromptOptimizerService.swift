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
            case .emptyPrompt: return "The prompt is empty."
            case .noProvider: return "Nessun provider AI selezionato."
            case .emptyResponse: return "The provider returned an empty response."
            case .streamError(let msg): return msg
            }
        }
    }

    /// System prompt per l'ottimizzazione. Chiede al modello di restituire SOLO il prompt migliorato,
    /// nella stessa lingua dell'input, senza spiegazioni aggiuntive.
    private static let systemInstruction = """
    You are a prompt optimization expert. Your job is to take the user's prompt and rewrite it to be clearer, more specific, and more effective for an AI coding assistant.

    Rules:
    - Output ONLY the improved prompt, nothing else. No explanations, no preamble, no \"Here is the improved prompt:\" prefix.
    - Keep the SAME language as the input prompt. If the user writes in Italian, respond in Italian. If in English, respond in English. Etc.
    - Preserve the user's original intent and meaning.
    - Make it more specific, structured, and actionable.
    - Add relevant context clues if the original prompt is vague.
    - Keep a similar length — don't make it excessively longer.
    - If the prompt is already excellent, return it as-is with minimal changes.
    """

    /// Ottimizza il prompt usando il provider fornito.
    /// Returns the optimized text.
    static func optimize(
        prompt: String,
        using provider: any LLMProvider,
        context: WorkspaceContext
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OptimizeError.emptyPrompt }

        let userPrompt = """
        --- USER PROMPT TO OPTIMIZE ---
        \(trimmed)
        --- END ---
        """

        let ctx = WorkspaceContext.forPromptOptimizer(systemInstruction: systemInstruction)
        let stream = try await provider.send(
            prompt: userPrompt,
            context: ctx,
            imageURLs: nil
        )

        var parts: [String] = []
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                parts.append(delta)
            case .error(let msg):
                throw OptimizeError.streamError(msg)
            case .started, .completed, .raw:
                break
            }
        }

        let optimized = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !optimized.isEmpty else { throw OptimizeError.emptyResponse }
        return optimized
    }
}
