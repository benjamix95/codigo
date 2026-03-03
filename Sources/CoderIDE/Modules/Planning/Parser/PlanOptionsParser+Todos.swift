import Foundation

extension PlanOptionsParser {
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
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Self.foldingLocale)
                .lowercased()
            if normalized.isEmpty { return true }
            if normalized.range(of: #"^(?:pros?|cons?)\b"#, options: .regularExpression) != nil
                || normalized.hasPrefix("complexity")
                || normalized.hasPrefix("trade-off")
                || normalized.hasPrefix("tradeoff")
                || normalized.hasPrefix("option ")
                || normalized.hasPrefix("approach ") {
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
        var inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isFenceDelimiter(trimmed) { inFence.toggle(); continue }
            if inFence { continue }
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
        inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isFenceDelimiter(trimmed) { inFence.toggle(); continue }
            if inFence { continue }
            if let checklist = parseTaskLine(trimmed, allowPlainBullets: false) {
                appendTodo(checklist)
            }
        }
        if !todos.isEmpty { return todos }

        // 3) Fallback: pick the largest contiguous numbered/bulleted steps block.
        inFence = false
        var bestBlock: [String] = []
        var currentBlock: [String] = []
        for line in lines + [""] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isFenceDelimiter(trimmed) { inFence.toggle(); continue }
            if inFence { continue }
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
}
