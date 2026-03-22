import Foundation

/// Predefined question templates for each debug phase.
/// These are injected into agent prompts so the agent knows WHAT to ask.
public enum DebugQuestionTemplates {
    /// Questions the agent should ask during the Describing phase.
    public static func describingQuestions(errorSummary: String) -> [String] {
        var questions: [String] = []
        if errorSummary.isEmpty {
            questions.append("What error or unexpected behavior are you experiencing?")
            questions.append("Can you share the full error message or stack trace?")
        } else {
            questions.append("When did this issue first appear? Was there a recent change?")
            questions.append("Does this error happen consistently or intermittently?")
        }
        questions.append("Which part of the app is affected (UI, backend, build, tests)?")
        return questions
    }

    /// Questions the agent should ask during the Reproducing phase.
    public static func reproducingQuestions() -> [String] {
        [
            "What are the exact steps to reproduce this bug?",
            "What is the expected behavior vs actual behavior?",
            "Does the issue happen in a specific environment (simulator, device, OS version)?",
            "Are there specific inputs or data states that trigger the bug?"
        ]
    }

    /// Questions the agent should present when proposing hypotheses.
    public static func fixingQuestions(hypotheses: [String]) -> [String] {
        var questions: [String] = []
        if hypotheses.isEmpty {
            questions.append("Based on the analysis, I need to form hypotheses. Can you provide any additional context about what might have changed?")
        } else {
            questions.append("I've proposed \(hypotheses.count) hypothesis(es). Do any of these align with what you've observed?")
            questions.append("Should I proceed with the most likely hypothesis, or investigate further?")
        }
        return questions
    }

    /// Questions for verification before cleanup.
    public static func verifyingQuestions() -> [String] {
        [
            "The fix has been applied. Can you verify the bug is resolved?",
            "Have you tested the fix with the same reproduction steps?",
            "Are there any related areas that should be tested for regressions?"
        ]
    }

    /// Builds a prompt snippet with questions for the current stage.
    public static func promptSnippet(
        for stage: String,
        errorSummary: String = "",
        hypotheses: [String] = []
    ) -> String {
        let questions: [String]
        switch stage {
        case "gather_context", "analyze_issue":
            questions = describingQuestions(errorSummary: errorSummary)
        case "request_reproduction", "reproduce":
            questions = reproducingQuestions()
        case "fix":
            questions = fixingQuestions(hypotheses: hypotheses)
        case "verify":
            questions = verifyingQuestions()
        default:
            return ""
        }

        guard !questions.isEmpty else { return "" }

        var snippet = "\n\nSUGGESTED QUESTIONS TO ASK THE USER:\n"
        for (i, q) in questions.enumerated() {
            snippet += "\(i + 1). \(q)\n"
        }
        snippet += "\nUse `debug_request_user` to ask these questions. Do NOT proceed without user input.\n"
        return snippet
    }
}
