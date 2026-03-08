import Foundation

extension PlanOptionsParser {
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
                let headerKeywordPattern = #"(?i)(?:Option|Approach|Plan)\s+(\d+)"#
                if let headerDigitMatch = line.range(of: headerKeywordPattern, options: .regularExpression),
                   let digitsRegex = Self.digitsRegex,
                   let digitMatch = digitsRegex.firstMatch(
                    in: String(line[headerDigitMatch]),
                    range: NSRange(0..<line[headerDigitMatch].count)
                   ),
                   let digitRange = Range(digitMatch.range, in: String(line[headerDigitMatch])),
                   let n = Int(String(String(line[headerDigitMatch])[digitRange])) {
                    num = n
                } else if let letterMatch = line.range(of: #"(?i)(?:Option|Approach|Plan)\s+([A-Z])"#, options: .regularExpression) {
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
                       next.range(of: nextOptionPattern, options: .regularExpression) != nil {
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

        // Fallback: numbered blocks "1. ..." or "1) ..." with substantial content.
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        var options: [(num: Int, title: String, full: String)] = []
        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            guard p.count >= 20 else { continue }
            if let regex = Self.fallbackNumberedRegex,
               let match = regex.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)),
               let r1 = Range(match.range(at: 1), in: p),
               let num = Int(p[r1]),
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
        let multilineOptionPattern =
            #"(?im)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)\s*[:\-\u{2013}\u{2014}]"#
        if text.range(of: multilineOptionPattern, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: taskHeaderPatternForSignals, options: .regularExpression) != nil {
            return true
        }

        let numberedLinePattern = #"(?im)^\s*(?:\d+|[A-Za-z])[.)]\s+"#
        let checklistPattern = #"(?im)^\s*[-*•]\s*\[[ xX ]?\]"#
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
}
