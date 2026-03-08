import Foundation

enum BugHunterPromptBuilder {
    static func prompt(
        scopeTag: String,
        profile: BugHunterProfile,
        commitWindow: BugHunterCommitWindow? = nil,
        autoFixMode: BugHunterAutofixMode,
        maxAutoRounds: Int
    ) -> String {
        var sections: [String] = [
            "\(scopeTag) [MODE:bug-hunter-ultra]",
            """
            Run an ultra-deep bug hunt.
            Requirements:
            - prioritize correctness, regressions, crash paths, concurrency, API contract drift, and test impact;
            - use audit_run_profile(profile=bug_hunt_deep) or a stricter profile when relevant;
            - correlate signals before promoting verified bugs;
            - do not emit speculative verified bugs;
            - only mark bugs autofixable when patch verification is realistic.
            """,
            """
            BugHunter profile: \(profile.rawValue)
            Autofix mode: \(autoFixMode.rawValue)
            Max auto rounds: \(maxAutoRounds)
            """,
        ]

        if let commitWindow {
            sections.append(
                """
                Primary commit: \(commitWindow.primaryCommit)
                Related commits: \(commitWindow.relatedCommits.joined(separator: ", "))
                Files in focus:
                \(commitWindow.files.joined(separator: "\n"))
                """
            )
        }

        sections.append(
            """
            Output requirements:
            1. verified bugs first, with evidence and confidence
            2. candidates separately, clearly marked
            3. autofixable verified bugs separately
            4. regression surface across the selected scope
            5. if clean, state that explicitly
            """
        )
        return sections.joined(separator: "\n\n")
    }
}
