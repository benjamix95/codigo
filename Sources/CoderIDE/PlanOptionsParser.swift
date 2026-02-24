import Foundation

/// Option extracted from an AI plan.
struct PlanOption: Identifiable, Equatable, Codable {
    let id: Int
    let title: String
    let fullText: String
}

struct PlanClarificationOption: Identifiable, Equatable, Codable {
    let id: String
    let text: String
}

struct PlanClarificationQuestion: Identifiable, Equatable, Codable {
    let id: Int
    let prompt: String
    let options: [PlanClarificationOption]
}

struct PlanClarificationQuestionnaire: Equatable, Codable {
    let questions: [PlanClarificationQuestion]
}

struct PlanClarificationAnswer: Identifiable, Equatable {
    let questionId: Int
    let question: String
    let optionId: String
    let optionText: String
    let customResponse: String?

    var id: Int { questionId }
}

struct PlanClarificationSubmission: Equatable {
    let answers: [PlanClarificationAnswer]
    let finalMandatoryNote: String
}

/// Extracts numbered options from plan text (e.g. "## Option 1: ...", "Option 2:", etc.).
enum PlanOptionsParser {
    private static let optionHeaderPattern =
        #"(?i)(?:Opzione|Option|Approccio|Approach)\s+(?:\d+|[A-Z])\s*[:\-\u{2013}\u{2014}]"#
    private static let nextOptionPattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:Opzione|Option|Approccio|Approach)\s+(?:\d+|[A-Z])"#
    private static let optionWithTitlePattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:Opzione|Option|Approccio|Approach)\s+(?:\d+|[A-Z])\s*[:\-\u{2013}\u{2014}]\s*.+$"#
    private static let clarificationHeaderPattern =
        #"(?im)^\s*#{1,3}\s*(?:Domande\s+di\s+chiarimento|Clarification\s*questions|Questions\s*to\s*clarify|Questions)\s*:?\s*$"#
    private static let otherLikePrimaryTokens: Set<String> = [
        "other",
        "altro",
        "altra",
        "custom",
    ]
    private static let otherLikeContextualTokens: Set<String> = ["specifica", "specify"]

    static func isOtherLikeClarificationOption(_ option: PlanClarificationOption) -> Bool {
        let normalized = option.text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
        let questionPattern = #"^\s*(\d+)[.)]\s*(.+)$"#
        let optionPattern = #"^\s*(?:[-*•]\s*)?([A-Za-z])[.)]\s+(.+)$"#
        let questionRegex = try? NSRegularExpression(pattern: questionPattern)
        let optionRegex = try? NSRegularExpression(pattern: optionPattern)

        func flushQuestion() {
            guard let questionId = currentQuestionId else { return }
            let prompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, currentOptions.count >= 2 else {
                isInvalidStructuredBlock = true
                return
            }
            parsedQuestions.append(
                PlanClarificationQuestion(
                    id: questionId,
                    prompt: prompt,
                    options: currentOptions
                )
            )
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

            if let questionRegex,
               let match = questionRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let idRange = Range(match.range(at: 1), in: trimmed),
               let promptRange = Range(match.range(at: 2), in: trimmed),
               let parsedId = Int(trimmed[idRange])
            {
                flushQuestion()
                if isInvalidStructuredBlock { return nil }
                currentQuestionId = parsedId
                currentPrompt = String(trimmed[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                currentOptions = []
                continue
            }

            if let optionRegex,
               let match = optionRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let keyRange = Range(match.range(at: 1), in: trimmed),
               let textRange = Range(match.range(at: 2), in: trimmed),
               currentQuestionId != nil
            {
                let optionId = String(trimmed[keyRange]).uppercased()
                let optionText = String(trimmed[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if optionText.isEmpty {
                    isInvalidStructuredBlock = true
                    return nil
                }
                currentOptions.append(PlanClarificationOption(id: optionId, text: optionText))
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
                currentOptions[currentOptions.count - 1] = PlanClarificationOption(id: lastOption.id, text: merged)
            }
        }

        flushQuestion()
        guard !isInvalidStructuredBlock, !parsedQuestions.isEmpty else { return nil }
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
        let numberedPattern = #"^\s*(\d+)[.)]\s*(.+)$"#
        let bulletPattern = #"^\s*[-*•]\s+(.+)$"#
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: clarificationHeaderPattern, options: .regularExpression) != nil {
                inBlock = true
                continue
            }
            if inBlock {
                // Exit the block if another Markdown heading is found.
                if trimmed.hasPrefix("#") {
                    break
                }
                if trimmed.isEmpty { continue }
                if let regex = try? NSRegularExpression(pattern: numberedPattern),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let r2 = Range(match.range(at: 2), in: trimmed) {
                    let q = String(trimmed[r2]).trimmingCharacters(in: .whitespaces)
                    if !q.isEmpty { questions.append(q) }
                } else if let regex = try? NSRegularExpression(pattern: bulletPattern),
                          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                          let r1 = Range(match.range(at: 1), in: trimmed) {
                    let q = String(trimmed[r1]).trimmingCharacters(in: .whitespaces)
                    if !q.isEmpty { questions.append(q) }
                }
            }
        }
        return questions.isEmpty ? nil : questions
    }

    private static func parseStructured(from text: String) -> [PlanOption] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var options: [(num: Int, title: String, full: String)] = []
        let lines = trimmed.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Match "Option 1:" / "Approach A:" or with Markdown heading.
            if line.range(of: optionHeaderPattern, options: .regularExpression) != nil {
                var num = 0
                var title = "Option"
                if let digitsRegex = try? NSRegularExpression(pattern: #"\d+"#),
                   let digitMatch = digitsRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let digitRange = Range(digitMatch.range, in: line),
                   let n = Int(String(line[digitRange])) {
                    num = n
                }

                let separators = [":", "-", "–", "—"]
                if let sepRange = separators.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                    let rawTitle = String(line[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !rawTitle.isEmpty {
                        title = rawTitle
                    } else {
                        title = "Opzione \(max(num, 1))"
                    }
                } else {
                    title = "Opzione \(max(num, 1))"
                }

                var fullLines = [line]
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    if next.range(of: nextOptionPattern, options: .regularExpression) != nil {
                        break
                    }
                    fullLines.append(next)
                    i += 1
                }
                let fullText = fullLines.joined(separator: "\n")
                options.append((num, title, fullText))
                continue
            }
            i += 1
        }

        if !options.isEmpty {
            return options.sorted(by: { $0.num < $1.num }).map {
                PlanOption(id: $0.num, title: $0.title, fullText: $0.full)
            }
        }
        return []
    }

    /// Restituisce solo opzioni strutturate e affidabili per transizioni di stato/build.
    static func parseStrict(from text: String) -> [PlanOption] {
        let options = parseStructured(from: text)
        guard !options.isEmpty else { return [] }

        // Hardening: evita falsi positivi su testo rumoroso. Richiedi almeno due opzioni
        // oppure heading opzione completo con titolo.
        if options.count >= 2 { return options }
        guard options.count == 1 else { return [] }
        let firstLine = options[0].fullText.components(separatedBy: .newlines).first ?? ""
        let hasStrongHeader = firstLine.range(of: optionWithTitlePattern, options: .regularExpression) != nil
        return hasStrongHeader ? options : []
    }

    /// Restituisce le opzioni parsegate o una singola opzione con l'intero testo se il parsing fallisce
    static func parse(from text: String) -> [PlanOption] {
        let strict = parseStrict(from: text)
        if !strict.isEmpty { return strict }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Fallback: blocchi numerati "1. ..." o "1) ..." con contenuto lungo
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        var options: [(num: Int, title: String, full: String)] = []
        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            guard p.count >= 20 else { continue }
            if let regex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s*(.+)"#),
               let match = regex.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)),
               let r1 = Range(match.range(at: 1), in: p), let num = Int(p[r1]),
               num >= 1, num <= 20 {
                let content: String
                if match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: p) {
                    content = String(p[r2])
                } else {
                    content = p
                }
                let title = String(content.prefix(80))
                options.append((num, title, p))
            }
        }

        if !options.isEmpty {
            return options.sorted(by: { $0.num < $1.num }).map {
                PlanOption(id: $0.num, title: $0.title, fullText: $0.full)
            }
        }

        // Ultimo fallback: intero testo come unica opzione
        return [PlanOption(id: 1, title: "Full plan", fullText: trimmed)]
    }

    static func isFallbackOption(_ option: PlanOption) -> Bool {
        option.id == 1 && option.title == "Full plan"
    }

    /// Extracts todo steps from the "## Todo" section of a plan option.
    /// Cerca righe "- [ ] step" o "- step" e restituisce i titoli.
    static func extractTodosFromOptionText(_ optionText: String) -> [String] {
        let lines = optionText.components(separatedBy: .newlines)
        var inTodoSection = false
        var todos: [String] = []
        let todoHeaderPattern = #"(?i)##\s*Todo"#
        let checklistPattern = #"^\s*-\s*\[\s*\]\s*(.+)$"#
        let bulletPattern = #"^\s*-\s+(.+)$"#
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: todoHeaderPattern, options: .regularExpression) != nil {
                inTodoSection = true
                continue
            }
            if inTodoSection {
                if trimmed.hasPrefix("##") { break }
                if trimmed.isEmpty { continue }
                if let regex = try? NSRegularExpression(pattern: checklistPattern),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let r1 = Range(match.range(at: 1), in: trimmed) {
                    let title = String(trimmed[r1]).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { todos.append(title) }
                } else if let regex = try? NSRegularExpression(pattern: bulletPattern),
                          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                          let r1 = Range(match.range(at: 1), in: trimmed) {
                    let title = String(trimmed[r1]).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty, !title.hasPrefix("[") { todos.append(title) }
                }
            }
        }
        return todos
    }

    static func extractDisplaySummary(from fullPlan: String) -> (title: String, body: String) {
        let lines = fullPlan
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return ("Piano", "")
        }

        let titleLine = lines.first(where: { $0.hasPrefix("#") }) ?? lines[0]
        let title = titleLine.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyLines = Array(lines.dropFirst().prefix(20))
        let body = bodyLines.joined(separator: "\n")
        return (title.isEmpty ? "Piano" : title, body)
    }
}
