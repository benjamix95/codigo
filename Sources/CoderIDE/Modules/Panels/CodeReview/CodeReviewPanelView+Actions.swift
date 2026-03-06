import Foundation

extension CodeReviewPanelView {
    // MARK: - Actions

    struct SlashCommand: Identifiable {
        let id: String
        let slash: String
        let label: String
        let prompt: String
    }

    var slashCommands: [SlashCommand] {
        CodeReviewQuickCommands.defaults.map {
            SlashCommand(id: $0.id, slash: $0.slash, label: $0.label, prompt: $0.prompt)
        }
    }

    func runAgainstCommitReview() {
        let ref = againstCommitRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }
        onDispatchAction(
            .againstCommit(
                ref: ref,
                autofixEnabled: autofixEnabled,
                maxRounds: codeReviewMaxRounds
            )
        )
    }

    func isValidGitRef(_ ref: String) -> Bool {
        isValidGitRefFormat(ref)
    }
}
