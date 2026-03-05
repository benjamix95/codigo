import Foundation

extension PlanOptionsParser {
    static func isOtherLikeClarificationOption(_ option: PlanClarificationOption) -> Bool {
        let normalized = option.text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: foldingLocale)
            .lowercased()
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.contains(where: { otherLikePrimaryTokens.contains($0) }) {
            return true
        }
        if tokens.contains(where: { otherLikeContextualTokens.contains($0) }) {
            return normalized.hasPrefix("specifica")
                || normalized.hasPrefix("specify")
                || normalized.contains("(specifica")
                || normalized.contains("(specify")
                || normalized.contains("specifica:")
                || normalized.contains("specify:")
        }
        return false
    }

    static func parseClarificationQuestionnaire(from text: String) -> PlanClarificationQuestionnaire? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.range(of: clarificationHeaderPattern, options: .regularExpression) != nil else {
            return nil
        }

        let lines = normalized.components(separatedBy: .newlines)
        var inBlock = false
        var parsedQuestions: [PlanClarificationQuestion] = []
        var currentQuestionId: Int?
        var currentPrompt = ""
        var currentOptions: [PlanClarificationOption] = []
        var isInvalidStructuredBlock = false

        var currentHasCheckboxOptions = false

        func flushQuestion() {
            guard let questionId = currentQuestionId else { return }
            var prompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, currentOptions.count >= 2 else {
                isInvalidStructuredBlock = true
                return
            }
            // Detect multi-select: text marker in prompt or checkbox-style options.
            let hasTextMarker = prompt.range(of: Self.multiSelectPattern, options: .regularExpression) != nil
            let isMulti = hasTextMarker || currentHasCheckboxOptions
            // Strip the multi-select marker from displayed prompt.
            if hasTextMarker {
                prompt = prompt.replacingOccurrences(
                    of: Self.multiSelectPattern,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+([?.!,:;])"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            parsedQuestions.append(
                PlanClarificationQuestion(
                    id: questionId,
                    prompt: prompt,
                    options: currentOptions,
                    isMultiSelect: isMulti
                )
            )
            currentHasCheckboxOptions = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: clarificationHeaderPattern, options: .regularExpression) != nil {
                inBlock = true
                continue
            }
            if !inBlock { continue }
            if trimmed.hasPrefix("#") { break }
            if trimmed.isEmpty { continue }

            if let qRegex = Self.questionRegex,
               let match = qRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let idRange = Range(match.range(at: 1), in: trimmed),
               let promptRange = Range(match.range(at: 2), in: trimmed),
               let parsedId = Int(trimmed[idRange])
            {
                flushQuestion()
                if isInvalidStructuredBlock { return nil }
                currentQuestionId = parsedId
                currentPrompt = String(trimmed[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                currentOptions = []
                currentHasCheckboxOptions = false
                continue
            }

            if let oRegex = Self.clarificationOptionRegex,
               let match = oRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let keyRange = Range(match.range(at: 1), in: trimmed),
               let textRange = Range(match.range(at: 2), in: trimmed),
               currentQuestionId != nil
            {
                let optionId = String(trimmed[keyRange]).uppercased()
                var optionText = String(trimmed[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if optionText.isEmpty {
                    isInvalidStructuredBlock = true
                    return nil
                }
                // Detect and strip "(Recommended)" marker from option text.
                let recommendedPattern = #"\s*\((?i:recommended|consigliato|consigliata)\)\s*$"#
                let isRecommended = optionText.range(of: recommendedPattern, options: .regularExpression) != nil
                if isRecommended {
                    optionText = optionText.replacingOccurrences(
                        of: recommendedPattern,
                        with: "",
                        options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // Detect checkbox-style options: "- [ ] A)" or "- [x] B)"
                if trimmed.range(of: Self.checkboxOptionPattern, options: .regularExpression) != nil {
                    currentHasCheckboxOptions = true
                }
                currentOptions.append(
                    PlanClarificationOption(
                        id: optionId,
                        text: optionText,
                        isRecommended: isRecommended
                    )
                )
                continue
            }

            if currentQuestionId == nil {
                isInvalidStructuredBlock = true
                return nil
            }

            if currentOptions.isEmpty {
                currentPrompt = "\(currentPrompt) \(trimmed)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let lastOption = currentOptions.last {
                let merged = "\(lastOption.text) \(trimmed)".trimmingCharacters(in: .whitespacesAndNewlines)
                currentOptions[currentOptions.count - 1] = PlanClarificationOption(
                    id: lastOption.id,
                    text: merged,
                    isRecommended: lastOption.isRecommended
                )
            }
        }

        flushQuestion()
        // If only the final question was invalid (truncated stream), keep previously valid questions.
        if isInvalidStructuredBlock && parsedQuestions.isEmpty { return nil }
        guard !parsedQuestions.isEmpty else { return nil }
        return PlanClarificationQuestionnaire(questions: parsedQuestions)
    }

    /// Extracts clarification questions from the "## Questions" block.
    /// Returns nil if no clarification block is found (then proceed with option parsing).
    static func parseClarificationQuestions(from text: String) -> [String]? {
        if let structured = parseClarificationQuestionnaire(from: text) {
            return structured.questions.map(\.prompt)
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        // Search for Markdown heading "#/##/### Questions" or variants.
        guard normalized.range(of: clarificationHeaderPattern, options: .regularExpression) != nil else {
            return nil
        }
        let lines = normalized.components(separatedBy: .newlines)
        var inBlock = false
        var questions: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: clarificationHeaderPattern, options: .regularExpression) != nil {
                inBlock = true
                continue
            }
            if inBlock {
                if trimmed.hasPrefix("#") {
                    break
                }
                if trimmed.isEmpty { continue }
                if let regex = Self.questionRegex,
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let r2 = Range(match.range(at: 2), in: trimmed) {
                    let q = String(trimmed[r2]).trimmingCharacters(in: .whitespaces)
                    if !q.isEmpty { questions.append(q) }
                } else if let regex = Self.bulletLineRegex,
                          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                          let r1 = Range(match.range(at: 1), in: trimmed) {
                    let q = String(trimmed[r1]).trimmingCharacters(in: .whitespaces)
                    if !q.isEmpty { questions.append(q) }
                }
            }
        }
        return questions.isEmpty ? nil : questions
    }
}
