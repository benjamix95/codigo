import Foundation

struct DebugClarificationSubmission: Equatable {
    let agentPrompt: String
    let chatDisplayText: String
}

enum DebugClarificationSubmissionComposer {
    static let maskedChatDisplayText = "altro"

    static func compose(
        parsed: DebugClarificationPromptParser.Parsed,
        selectedLetter: String?,
        customNotes: String
    ) -> DebugClarificationSubmission? {
        var lines: [String] = ["[Risposta dal pannello Debug — chiarimento]"]
        let trimmedCustomNotes = customNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let selectedLetter,
           let chosen = parsed.options.first(where: { $0.letter == selectedLetter }) {
            lines.append("Scelta: (\(chosen.letter)) \(chosen.text)")
        }
        if !trimmedCustomNotes.isEmpty {
            lines.append("Dettagli / contesto: \(trimmedCustomNotes)")
        }

        let agentPrompt = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard agentPrompt != "[Risposta dal pannello Debug — chiarimento]" else {
            return nil
        }

        return DebugClarificationSubmission(
            agentPrompt: agentPrompt,
            chatDisplayText: maskedChatDisplayText
        )
    }
}
