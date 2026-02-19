import Foundation
import CoderEngine

struct GitCommitMessageGenerator {
    func generateCommitMessage(
        diff: String,
        provider: any LLMProvider,
        context: WorkspaceContext
    ) async throws -> String {
        let cappedDiff = String(diff.prefix(20_000))
        let prompt = """
        Genera un messaggio di commit Git conciso e professionale.
        Vincoli:
        - usa un subject singolo
        - massimo 72 caratteri
        - niente virgolette
        - preferisci stile conventional commit (feat/fix/chore/refactor/docs/test) quando sensato
        - rispondi SOLO con il subject

        Diff:
        \(cappedDiff)
        """
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: nil)
        var full = ""
        for try await ev in stream {
            if case .textDelta(let d) = ev { full += d }
        }
        let line = full
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard var msg = line, !msg.isEmpty else {
            throw NSError(domain: "GitCommitMessageGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Messaggio commit AI vuoto"])
        }
        if msg.count > 72 {
            msg = String(msg.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return msg
    }

    func fallbackMessage(from status: GitStatusSummary) -> String {
        if status.added > 0 && status.modified == 0 && status.removed == 0 {
            return "feat: add project updates"
        }
        if status.removed > 0 && status.added == 0 {
            return "refactor: remove obsolete files"
        }
        if status.modified > 0 {
            return "chore: update project files"
        }
        return "chore: update workspace"
    }
}
