import Foundation

struct CodeReviewQuickCommand: Identifiable {
    let id: String
    let slash: String
    let label: String
    let prompt: String
}

enum CodeReviewQuickCommands {
    static let defaults: [CodeReviewQuickCommand] = [
        CodeReviewQuickCommand(
            id: "review-uncommitted",
            slash: "/review-uncommitted",
            label: "Full uncommitted audit",
            prompt:
                """
                [REVIEW_SCOPE:uncommitted] Run ultra-deep code review on all uncommitted changes (staged, unstaged, untracked).
                Required output:
                1) prioritized findings (P0-P3),
                2) impacted areas file-by-file,
                3) regression risks,
                4) final verdict on patch correctness.
                """
        ),
        CodeReviewQuickCommand(
            id: "review-staged",
            slash: "/review-staged",
            label: "Staged diff only",
            prompt:
                """
                [REVIEW_SCOPE:staged] Review ONLY staged changes.
                Ignore unstaged and untracked.
                Return severe and actionable findings with priority/confidence.
                """
        ),
        CodeReviewQuickCommand(
            id: "review-autofix",
            slash: "/review-autofix",
            label: "Review + auto fix",
            prompt:
                """
                [REVIEW_SCOPE:uncommitted] Deep review uncommitted changes and directly fix all confirmed bugs.
                After fixes, run relevant build/tests and report the technical changelog.
                """
        ),
        CodeReviewQuickCommand(
            id: "review-autofix-commit",
            slash: "/review-autofix-commit",
            label: "Review + fix + commit",
            prompt:
                """
                [REVIEW_SCOPE:uncommitted] Run full review on staged/unstaged/untracked, apply necessary fixes and create final atomic commit.
                Requirements: no superfluous changes, green build/tests, specific commit message.
                """
        ),
        CodeReviewQuickCommand(
            id: "review-focus-ui",
            slash: "/review-focus-ui",
            label: "Focus UI flows",
            prompt:
                """
                [REVIEW_SCOPE:uncommitted] Focus on review realtime flows:
                - visible step-by-step stream,
                - live updated read/tool/terminal cards,
                - consistent todos without layout glitches.
                Fix any issues found and validate with tests/build.
                """
        ),
    ]

    static func againstPrompt(ref: String, autofixEnabled: Bool, maxRounds: Int) -> String {
        let suffix = autofixEnabled
            ? "\nAfter analysis, apply all confirmed fixes. Run build/tests and iterate up to \(maxRounds) rounds until clean."
            : "\nAnalysis only — report findings with priority/confidence, do NOT apply fixes."
        return """
            [AGAINST:\(ref)] Run deep code review on changes from \(ref) to HEAD.
            Scope: all modified, added, and renamed files in that range.
            Required output:
            1) prioritized findings (P0-P3) with file:line references,
            2) regression risks,
            3) final verdict on patch correctness.\(suffix)
            """
    }
}
