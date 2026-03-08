import Foundation

enum PlanClarificationQuestionnaireMarkdown {
    static func render(
        questionnaire: PlanClarificationQuestionnaire,
        header: String = "## Questions"
    ) -> String {
        let orderedQuestions = questionnaire.questions.sorted { $0.id < $1.id }
        guard !orderedQuestions.isEmpty else { return header }

        var lines: [String] = [header]
        for question in orderedQuestions {
            let prompt: String = {
                let trimmed = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Question \(question.id)?" }
                if question.isMultiSelect, !trimmed.lowercased().contains("select all that apply") {
                    return "\(trimmed) (select all that apply)"
                }
                return trimmed
            }()

            lines.append("\(question.id). \(prompt)")

            let orderedOptions = question.options.sorted { $0.id < $1.id }
            for option in orderedOptions {
                let optionText = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !optionText.isEmpty else { continue }
                let suffix = option.isRecommended ? " (Recommended)" : ""
                lines.append("\(option.id)) \(optionText)\(suffix)")
            }

            lines.append("")
        }

        while lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
