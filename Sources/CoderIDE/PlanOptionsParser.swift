import Foundation

/// Option extracted from an AI plan.
struct PlanOption: Identifiable, Equatable, Codable {
    let id: Int
    let title: String
    let fullText: String
}

struct PlanClarificationOption: Identifiable, Equatable, Codable, Hashable {
    let id: String
    let text: String
    let isRecommended: Bool

    init(id: String, text: String, isRecommended: Bool = false) {
        self.id = id
        self.text = text
        self.isRecommended = isRecommended
    }
}

struct PlanClarificationQuestion: Identifiable, Equatable, Codable {
    let id: Int
    let prompt: String
    let options: [PlanClarificationOption]
    let isMultiSelect: Bool

    init(id: Int, prompt: String, options: [PlanClarificationOption], isMultiSelect: Bool = false) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.isMultiSelect = isMultiSelect
    }
}

struct PlanClarificationQuestionnaire: Equatable, Codable {
    let questions: [PlanClarificationQuestion]
}

struct PlanClarificationAnswer: Identifiable, Equatable {
    let questionId: Int
    let question: String
    /// Primary selected option (first selection for multi-select, single for single-select)
    let optionId: String
    let optionText: String
    /// All selected option IDs (for multi-select questions)
    let optionIds: [String]
    /// All selected option texts (for multi-select questions)
    let optionTexts: [String]
    let customResponse: String?

    var id: Int { questionId }

    /// Convenience init for single-select backward compatibility
    init(questionId: Int, question: String, optionId: String, optionText: String, customResponse: String?) {
        self.questionId = questionId
        self.question = question
        self.optionId = optionId
        self.optionText = optionText
        self.optionIds = [optionId]
        self.optionTexts = [optionText]
        self.customResponse = customResponse
    }

    /// Full init for multi-select
    init(questionId: Int, question: String, optionId: String, optionText: String, optionIds: [String], optionTexts: [String], customResponse: String?) {
        self.questionId = questionId
        self.question = question
        self.optionId = optionId
        self.optionText = optionText
        self.optionIds = optionIds
        self.optionTexts = optionTexts
        self.customResponse = customResponse
    }
}

struct PlanClarificationSubmission: Equatable {
    let answers: [PlanClarificationAnswer]
    let finalNote: String
}

/// Extracts numbered options from plan text (e.g. "## Option 1: ...", "Option 2:", etc.).
enum PlanOptionsParser {
private static let optionHeaderPattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)\s*[:\-\u{2013}\u{2014}]"#
    private static let nextOptionPattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)"#
    private static let optionWithTitlePattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)\s*[:\-\u{2013}\u{2014}]\s*.+$"#
    private static let clarificationHeaderPattern =
        #"(?im)^\s*#{1,3}\s*(?:Clarification\s*questions|Questions\s*to\s*clarify|Questions)\s*:?\s*$"#
    private static let otherLikePrimaryTokens: Set<String> = [
        "other",
        "altro",
        "altra",
        "custom",
    ]
    private static let otherLikeContextualTokens: Set<String> = ["specifica", "specify"]

    // Pre-compiled regexes for hot paths
    private static let questionRegex = try? NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s*(.+)$"#)
    private static let clarificationOptionRegex = try? NSRegularExpression(pattern: #"^\s*(?:[-*•]\s*)?(?:\[\s*[xX ]?\s*\]\s*)?([A-Za-z])[.)]\s+(.+)$"#)
    /// Detects checkbox-style options: "- [ ] A) ..." or "- [x] B) ..."
    private static let checkboxOptionPattern = #"^\s*[-*•]\s*\[\s*[xX ]?\s*\]"#
    /// Detects multi-select markers in question text
    private static let multiSelectPattern = #"(?i)\(\s*(?:select\s+(?:all\s+that\s+apply|multiple)|multi[-\s]?select|seleziona\s+(?:tutto|multiplo|piu))\s*\)"#
    private static let numberedLineRegex = try? NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.+)$"#)
    private static let bulletLineRegex = try? NSRegularExpression(pattern: #"^\s*[-*•]\s+(.+)$"#)
    private static let checklistLineRegex = try? NSRegularExpression(pattern: #"^\s*[-*•]\s*\[\s*[xX ]\s*\]\s*(.+)$"#)
    private static let digitsRegex = try? NSRegularExpression(pattern: #"\d+"#)
    private static let fallbackNumberedRegex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s*(.+)"#)

    private static let taskHeaderPatternForSignals =
        #"(?i)^(?:#{1,6}\s*)?(?:todo|to-do|tasks?|implementation\s+steps?|execution\s+steps?|next\s+steps?|checklist|action\s+items?|work\s*plan)\b"#

    private static func isFenceDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

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

        var currentHasCheckboxOptions = false

        func flushQuestion() {
            guard let questionId = currentQuestionId else { return }
            var prompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, currentOptions.count >= 2 else {
                isInvalidStructuredBlock = true
                return
            }
            // Detect multi-select: text marker in prompt or checkbox-style options
            let hasTextMarker = prompt.range(of: Self.multiSelectPattern, options: .regularExpression) != nil
            let isMulti = hasTextMarker || currentHasCheckboxOptions
            // Strip the multi-select marker from displayed prompt
            if hasTextMarker {
                prompt = prompt.replacingOccurrences(
                    of: Self.multiSelectPattern, with: "", options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
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
                // Detect and strip "(Recommended)" marker from option text
                let recommendedPattern = #"\s*\((?i:recommended|consigliato|consigliata)\)\s*$"#
                let isRecommended = optionText.range(of: recommendedPattern, options: .regularExpression) != nil
                if isRecommended {
                    optionText = optionText.replacingOccurrences(
                        of: recommendedPattern, with: "", options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // Detect checkbox-style options: "- [ ] A)" or "- [x] B)"
                if trimmed.range(of: Self.checkboxOptionPattern, options: .regularExpression) != nil {
                    currentHasCheckboxOptions = true
                }
                currentOptions.append(PlanClarificationOption(id: optionId, text: optionText, isRecommended: isRecommended))
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

    private static func parseStructured(from text: String) -> [PlanOption] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var options: [(num: Int, title: String, full: String)] = []
        let lines = trimmed.components(separatedBy: .newlines)
        var inFence = false

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isFenceDelimiter(line) {
                inFence.toggle()
                i += 1
                continue
            }
            if inFence {
                i += 1
                continue
            }
            // Match "Option 1:" / "Approach A:" or with Markdown heading.
            if line.range(of: optionHeaderPattern, options: .regularExpression) != nil {
                var num = 0
                var title = "Option"
                if let digitsRegex = Self.digitsRegex,
                   let digitMatch = digitsRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let digitRange = Range(digitMatch.range, in: line),
                   let n = Int(String(line[digitRange])) {
                    num = n
                } else if let letterMatch = line.range(
                    of: #"(?i)(?:Option|Approach)\s+([A-Z])"#,
                    options: .regularExpression
                ) {
                    let matched = line[letterMatch]
                    if let letter = matched.last?.uppercased().first,
                       letter.isLetter {
                        num = Int(letter.asciiValue ?? 65) - 64 // A=1, B=2, ...
                    }
                }

                let separators = [":", "-", "–", "—"]
                if let sepRange = separators.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                    let rawTitle = String(line[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !rawTitle.isEmpty {
                        title = rawTitle
                    } else {
                        title = "Option \(max(num, 1))"
                    }
                } else {
                    title = "Option \(max(num, 1))"
                }

                var fullLines = [line]
                i += 1
                var inOptionFence = false
                while i < lines.count {
                    let next = lines[i]
                    if isFenceDelimiter(next) {
                        inOptionFence.toggle()
                    }
                    if !inOptionFence,
                       next.range(of: nextOptionPattern, options: .regularExpression) != nil
                    {
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

    /// Returns only structured, reliable options for phase transitions/build gating.
    static func parseStrict(from text: String) -> [PlanOption] {
        let options = parseStructured(from: text)
        guard !options.isEmpty else { return [] }

        // Hardening: avoid false positives on noisy text. Accept one option when it has
        // a strong heading + title (for the single-plan flow).
        if options.count > 1 { return options }
        let firstLine = options[0].fullText.components(separatedBy: .newlines).first ?? ""
        let hasStrongHeader = firstLine.range(of: optionWithTitlePattern, options: .regularExpression) != nil
        return hasStrongHeader ? options : []
    }

    /// Returns parsed options, or a single option with full text if parsing fails.
    static func parse(from text: String) -> [PlanOption] {
        let strict = parseStrict(from: text)
        if !strict.isEmpty { return strict }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Fallback: numbered blocks "1. ..." or "1) ..." with substantial content
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        var options: [(num: Int, title: String, full: String)] = []
        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            guard p.count >= 20 else { continue }
            if let regex = Self.fallbackNumberedRegex,
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

        // Final fallback: whole text as one option only when the payload looks
        // like a real plan document (to avoid accidental false positives).
        guard hasLikelyPlanSignal(in: trimmed) else { return [] }
        return [PlanOption(id: 1, title: "Full plan", fullText: trimmed)]
    }

    /// Parse plan output for classification decisions.
    /// Unlike `parse`, this excludes very low-confidence full-text fallbacks.
    static func parseForPlanClassification(from text: String) -> [PlanOption] {
        let strict = parseStrict(from: text)
        if !strict.isEmpty { return strict }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Reuse the permissive numbered paragraph fallback without accepting
        // low-signal full-text blobs.
        let fallbackOptions = parse(from: text)
        guard !fallbackOptions.isEmpty else { return [] }
        if fallbackOptions.count == 1, isFallbackOption(fallbackOptions[0]) {
            return hasLikelyPlanSignal(in: trimmed) ? fallbackOptions : []
        }
        return fallbackOptions
    }

    private static func hasLikelyPlanSignal(in text: String) -> Bool {
        if text.range(of: optionHeaderPattern, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: taskHeaderPatternForSignals, options: .regularExpression) != nil {
            return true
        }
        let numberedLinePattern = #"(?im)^\s*(?:\d+|[A-Za-z])[.)]\s+"#
        let checklistPattern = #"(?im)^\s*[-*•]\s*\[[ xX ]?\]?"#
        var inFence = false
        let lines = text.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            if isFenceDelimiter(line) {
                inFence.toggle()
                return false
            }
            return !inFence
        }
        let numberedCount = filteredLines.filter { line in
            line.range(of: numberedLinePattern, options: .regularExpression) != nil
        }.count
        if numberedCount >= 2 {
            return true
        }
        let checklistCount = filteredLines.filter { line in
            line.range(of: checklistPattern, options: .regularExpression) != nil
        }.count
        if checklistCount >= 2 {
            return true
        }
        return false
    }

    static func isFallbackOption(_ option: PlanOption) -> Bool {
        option.id == 1 && option.title == "Full plan"
    }

    private static func normalizeTodoText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackTodoFromPlanText(_ optionText: String) -> String? {
        let lines = optionText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let firstLine = lines.first(where: { !isFenceDelimiter($0) }) else {
            return nil
        }
        let normalized = normalizeTodoText(firstLine)
        guard !normalized.isEmpty else { return nil }
        let words = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        let truncated = normalized.count > 260
            ? String(normalized.prefix(260)) + "…"
            : normalized
        return truncated
    }

    static func hasRequiredTodoHeader(_ optionText: String) -> Bool {
        let todoHeaderPattern = #"(?im)\#(taskHeaderPatternForSignals)"#
        if optionText.range(of: todoHeaderPattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func isTodoCompliantOption(_ option: PlanOption) -> Bool {
        hasRequiredTodoHeader(option.fullText) && !extractTodosFromOptionText(option.fullText).isEmpty
    }

    static func todoCompliantOptions(from options: [PlanOption]) -> [PlanOption] {
        options.filter(isTodoCompliantOption)
    }

    /// Extracts executable todo steps from a plan option.
    /// Primary path requires a dedicated task section; fallback accepts explicit checklist/steps blocks.
    static func extractTodosFromOptionText(_ optionText: String) -> [String] {
        let lines = optionText.components(separatedBy: .newlines)
        let taskHeaderPattern =
            #"(?i)^(?:#{1,6}\s*)?(?:todo|to-do|tasks?|implementation\s+steps?|execution\s+steps?|next\s+steps?|checklist|action\s+items?|work\s*plan)\b"#

        var todos: [String] = []
        var seen = Set<String>()
        var inTaskSection = false

        func capture(_ text: String, regex: NSRegularExpression?) -> String? {
            guard let regex,
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func normalizeTodo(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: #"`"#, with: "")
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func shouldDiscard(_ title: String) -> Bool {
            let normalized = title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            if normalized.isEmpty { return true }
            if normalized.range(of: #"^(?:pros?|cons?)\b"#, options: .regularExpression) != nil
                || normalized.hasPrefix("complexity")
                || normalized.hasPrefix("trade-off")
                || normalized.hasPrefix("tradeoff")
                || normalized.hasPrefix("option ")
                || normalized.hasPrefix("approach ")
            {
                return true
            }
            return false
        }

        func appendTodo(_ raw: String) {
            let title = normalizeTodo(raw)
            guard !shouldDiscard(title) else { return }
            let key = title.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            todos.append(title)
        }

        func parseTaskLine(_ trimmed: String, allowPlainBullets: Bool) -> String? {
            if let checklist = capture(trimmed, regex: Self.checklistLineRegex) {
                return checklist
            }
            if allowPlainBullets, let bullet = capture(trimmed, regex: Self.bulletLineRegex) {
                return bullet
            }
            if allowPlainBullets, let numbered = capture(trimmed, regex: Self.numberedLineRegex) {
                return numbered
            }
            return nil
        }

        // 1) Dedicated task section ("## Todo", "Tasks", "Next steps", ...)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: taskHeaderPattern, options: .regularExpression) != nil {
                inTaskSection = true
                continue
            }
            if inTaskSection {
                if trimmed.hasPrefix("#") { break }
                if trimmed.isEmpty { continue }
                if let parsed = parseTaskLine(trimmed, allowPlainBullets: true) {
                    appendTodo(parsed)
                }
            }
        }
        if !todos.isEmpty { return todos }

        // 2) Explicit checklist anywhere in the option body.
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let checklist = parseTaskLine(trimmed, allowPlainBullets: false) {
                appendTodo(checklist)
            }
        }
        if !todos.isEmpty { return todos }

        // 3) Fallback: pick the largest contiguous numbered/bulleted steps block.
        var bestBlock: [String] = []
        var currentBlock: [String] = []
        for line in lines + [""] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = parseTaskLine(trimmed, allowPlainBullets: true) {
                currentBlock.append(parsed)
            } else {
                if currentBlock.count > bestBlock.count {
                    bestBlock = currentBlock
                }
                currentBlock.removeAll(keepingCapacity: true)
            }
        }
        if bestBlock.count >= 2 {
            for item in bestBlock {
                appendTodo(item)
            }
        }
        if !todos.isEmpty {
            return todos
        }
        return todos
    }

    static func extractDisplaySummary(from fullPlan: String) -> (title: String, body: String) {
        let lines = fullPlan
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return ("Plan", "")
        }

        let titleIndex = lines.firstIndex(where: { $0.hasPrefix("#") }) ?? 0
        let titleLine = lines[titleIndex]
        let title = titleLine.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop the title line itself to avoid it appearing in both title and body.
        var bodyLines = lines
        bodyLines.remove(at: titleIndex)
        let body = bodyLines.prefix(20).joined(separator: "\n")
        return (title.isEmpty ? "Plan" : title, body)
    }

    static func extractMermaidBlocksForDisplay(_ text: String) -> [String] {
        MermaidExtractor.extractMermaidBlocks(from: text)
    }

    static func extractPlanCauseSections(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let causeHeaders = [
            "cause",
            "root cause",
            "analysis",
            "approach",
            "rationale",
            "trade-off",
            "tradeoff",
            "constraints",
            "assumptions",
            // Technical plan headers
            "architecture",
            "design",
            "implementation",
            "technical",
            "system",
            "overview",
            "strategy",
            "plan",
            "summary",
            "scope",
            "dependencies",
            "risks",
            "migration",
            "refactor",
            "solution",
            "pipeline",
            "flow",
            "structure",
        ]
        let lines = trimmed.components(separatedBy: .newlines)
        var collected: [String] = []
        var current: [String] = []
        var collecting = false
        var inFence = false

        func flushCurrent() {
            let block = current
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty {
                collected.append(block)
            }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                inFence.toggle()
                if collecting {
                    current.append(line)
                }
                continue
            }
            if !inFence, trimmedLine.hasPrefix("#") {
                if collecting {
                    flushCurrent()
                    collecting = false
                }
                let title = trimmedLine
                    .drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
                    .lowercased()
                if causeHeaders.contains(where: { title.contains($0) }) {
                    collecting = true
                    current.append(line)
                }
                continue
            }
            if collecting {
                current.append(line)
            }
        }

        if collecting {
            flushCurrent()
        }
        return collected
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractFinalPlanBodyExcludingQuestionsOptionsTodos(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Prefer cause/technical sections when available, but don't discard other body content.
        let causeSections = extractPlanCauseSections(trimmed)

        let lines = trimmed.components(separatedBy: .newlines)
        var output: [String] = []
        var inFence = false
        var skippingSection = false

        func isSkippableHeader(_ line: String) -> Bool {
            let normalized = line
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ":", with: "")
            guard normalized.hasPrefix("#") else { return false }
            let title = normalized
                .drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
            // Note: "approach" removed — it's valuable technical plan content
            return title.hasPrefix("questions")
                || title.hasPrefix("clarification")
                || title.hasPrefix("option")
                || title.hasPrefix("todo")
                || title.hasPrefix("to-do")
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                if trimmedLine.lowercased().hasPrefix("```mermaid") {
                    // Mermaid is rendered in a dedicated section in the panel.
                    inFence = true
                    skippingSection = true
                    continue
                }
                inFence.toggle()
                if skippingSection {
                    if !inFence {
                        skippingSection = false
                    }
                    continue
                }
                output.append(line)
                continue
            }

            if inFence {
                if !skippingSection {
                    output.append(line)
                }
                continue
            }

            if trimmedLine.hasPrefix("#") {
                if isSkippableHeader(trimmedLine) {
                    skippingSection = true
                    continue
                }
                skippingSection = false
                output.append(line)
                continue
            }

            if skippingSection {
                continue
            }
            output.append(line)
        }

        let cleaned = output
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Combine cause sections (if any) with the filtered body content.
        // Cause sections provide structured technical content; the filtered body may add
        // remaining context not captured by the cause header matching.
        let combined: String
        if !causeSections.isEmpty && !cleaned.isEmpty {
            combined = "\(causeSections)\n\n\(cleaned)"
        } else if !causeSections.isEmpty {
            combined = causeSections
        } else if !cleaned.isEmpty {
            combined = cleaned
        } else {
            // Fallback: keep original text but remove mermaid fences to avoid duplication.
            let withoutMermaid = trimmed.replacingOccurrences(
                of: #"(?is)```mermaid\s+.*?```"#,
                with: "",
                options: .regularExpression
            )
            combined = withoutMermaid
        }

        return combined
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
