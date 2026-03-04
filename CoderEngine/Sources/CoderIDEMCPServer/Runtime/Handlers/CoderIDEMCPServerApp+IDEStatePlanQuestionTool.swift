import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handlePlanRequestUserInput(args: [String: String]) -> CallTool.Result {
        guard let questions = parseJSONObjectArray(args["questions"]), !questions.isEmpty else {
            return planError("Error: 'questions' must be a non-empty JSON array")
        }

        if questions.count > 6 {
            return planError("Error: 'questions' supports up to 6 items per call")
        }

        if let validationError = validatePlanRequestQuestions(questions) {
            return planError(validationError)
        }

        let title = sanitizedText(args["title"]) ?? "Clarification questions"
        let phase = sanitizedText(args["phase"]) ?? "questioning"
        let round = sanitizedText(args["round"]) ?? "n/a"
        let context = sanitizedText(args["context"])
        let contextSuffix = context.map { " | context: \($0)" } ?? ""

        return planOK(
            "OK — queued \(questions.count) clarification question(s) [title: \(title) | phase: \(phase) | round: \(round)]\(contextSuffix)"
        )
    }

    private static func validatePlanRequestQuestions(_ questions: [[String: Any]]) -> String? {
        for (index, question) in questions.enumerated() {
            let prompt = (
                sanitizedText(question["prompt"] as? String)
                    ?? sanitizedText(question["question"] as? String)
                    ?? sanitizedText(question["title"] as? String)
                    ?? ""
            )
            if prompt.isEmpty {
                return "Error: questions[\(index)] requires a non-empty 'prompt' (or 'question')"
            }

            guard let options = normalizedQuestionOptions(question["options"]) else {
                return "Error: questions[\(index)] requires an 'options' array"
            }
            if options.count < 2 {
                return "Error: questions[\(index)] must provide at least 2 options"
            }
            if options.count > 5 {
                return "Error: questions[\(index)] supports at most 5 options"
            }
        }
        return nil
    }

    private static func normalizedQuestionOptions(_ raw: Any?) -> [String]? {
        if let textOptions = raw as? [String] {
            let normalized = textOptions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return normalized.isEmpty ? nil : normalized
        }

        guard let objectOptions = raw as? [[String: Any]] else {
            return nil
        }

        let normalized = objectOptions.compactMap { option -> String? in
            let label = (
                sanitizedText(option["label"] as? String)
                    ?? sanitizedText(option["text"] as? String)
                    ?? sanitizedText(option["title"] as? String)
                    ?? sanitizedText(option["content"] as? String)
            )
            return label
        }

        return normalized.isEmpty ? nil : normalized
    }
}
