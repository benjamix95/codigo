import CoderEngine
import Foundation

/// Genera il contenuto Markdown di una skill (stile Cursor) usando il provider selezionato, in modalità solo testo (systemPromptOverride).
enum SkillMarkdownAIService {
    private static func systemPrompt(skillTitle: String) -> String {
        """
        You write project "skills" for an AI coding assistant. A skill is a short Markdown document (Italian or English matching the user's request) that tells WHEN to apply guidance and WHAT to do.

        Output rules:
        - Return ONLY valid Markdown. No fences, no preamble, no "Here is...".
        - Start with a single H1 line: # \(skillTitle)
        - Include sections such as: Purpose, When to use, Steps / Checklist, Constraints (only if useful).
        - Be concrete and actionable; keep under ~120 lines unless the user asks for more detail.
        """
    }

    static func generate(
        skillFileNameStem: String,
        userRequest: String,
        provider: any LLMProvider,
        projectRoot: String?
    ) async throws -> String {
        let title = skillFileNameStem
            .replacingOccurrences(of: ".md", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? "Skill" : title

        let roots: [URL]
        if let projectRoot, !projectRoot.isEmpty {
            roots = [URL(fileURLWithPath: projectRoot)]
        } else {
            roots = [URL(fileURLWithPath: "/tmp")]
        }

        let ctx = WorkspaceContext(
            workspacePaths: roots,
            openFiles: [],
            skipContextEnrichment: true,
            systemPromptOverride: systemPrompt(skillTitle: safeTitle)
        )

        let hint = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let userBlock: String
        if hint.isEmpty {
            userBlock = """
            Project context: Solo Code user. Create a useful general-purpose coding skill for this project.
            Prefer practical checks (tests, style, security) appropriate to a macOS Swift app repo if unknowable.
            """
        } else {
            userBlock = "User request (follow closely):\n\(hint)"
        }

        let stream = try await provider.send(prompt: userBlock, context: ctx, imageURLs: nil)
        var parts: [String] = []
        for try await event in stream {
            switch event {
            case .textDelta(let d): parts.append(d)
            case .textReplace(let r): parts = r.isEmpty ? [] : [r]
            case .error(let msg): throw NSError(
                domain: "SkillMarkdownAIService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
            case .started, .completed, .raw:
                break
            }
        }
        let md = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !md.isEmpty else {
            throw NSError(
                domain: "SkillMarkdownAIService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "La risposta dell’AI è vuota."]
            )
        }
        return md
    }
}
