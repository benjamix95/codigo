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

    /// Builds a model-aware system instruction for prompt optimization.
    static func systemInstruction(modelName: String) -> String {
        """
        You are a prompt optimization expert. Rewrite the user's prompt to be maximally effective for \(modelName).

        Rules:
        - Output ONLY the improved prompt. No explanations, no preamble.
        - Keep the SAME language as the input.
        - Preserve original intent. Make it specific, structured, actionable.
        - Tailor to \(modelName) strengths (tool use, reasoning, code generation).
        - Similar length — don't bloat.
        - If already excellent, return as-is.
        """
    }

    /// Ottimizza il prompt usando il provider fornito.
    static func optimize(
        prompt: String,
        using provider: any LLMProvider,
        context: WorkspaceContext,
        modelName: String = "AI coding assistant"
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OptimizeError.emptyPrompt }

        let userPrompt = """
        --- USER PROMPT TO OPTIMIZE ---
        \(trimmed)
        --- END ---
        """

        let ctx = WorkspaceContext(
            workspacePaths: context.workspacePaths,
            isNamedWorkspace: context.isNamedWorkspace,
            workspaceName: context.workspaceName,
            excludedPaths: context.excludedPaths,
            includedPaths: context.includedPaths,
            openFiles: [],
            activeSelection: nil,
            activeFilePath: nil,
            activeRootPath: context.activeRootPath,
            skipContextEnrichment: true,
            systemPromptOverride: context.systemPromptOverride ?? systemInstruction(modelName: modelName)
        )
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
            case .textReplace(let replacement):
                parts = replacement.isEmpty ? [] : [replacement]
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
