import Foundation

/// Extracts numbered options from plan text (e.g. "## Option 1: ...", "Option 2:", etc.).
enum PlanOptionsParser {
    static let optionHeaderPattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)\s*[:\-\u{2013}\u{2014}]"#
    static let nextOptionPattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)"#
    static let optionWithTitlePattern =
        #"(?i)^\s*(?:#{1,3}\s*)?(?:(?:Option|Approach)\s+(?:\d+|[A-Z])|Plan(?:\s+(?:\d+|[A-Z]))?)\s*[:\-\u{2013}\u{2014}]\s*.+$"#
    static let clarificationHeaderPattern =
        #"(?im)^\s*#{1,3}\s*(?:Clarification\s*questions|Questions\s*to\s*clarify|Questions|Clarifications?\s*Needed|Need(?:ed)?\s*Clarifications?)\s*:?\s*$"#
    static let otherLikePrimaryTokens: Set<String> = [
        "other",
        "altro",
        "altra",
        "custom",
    ]
    static let otherLikeContextualTokens: Set<String> = ["specifica", "specify"]

    // Pre-compiled regexes for hot paths
    static let questionRegex = try? NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s*(.+)$"#)
    static let clarificationOptionRegex = try? NSRegularExpression(pattern: #"^\s*(?:[-*•]\s*)?(?:\[\s*[xX ]?\s*\]\s*)?([A-Za-z])[.)]\s+(.+)$"#)
    static let clarificationNumericOptionRegex = try? NSRegularExpression(pattern: #"^\s*(?:[-*•]\s*)?(?:\[\s*[xX ]?\s*\]\s*)?(\d{1,2})\)\s+(.+)$"#)
    static let clarificationBulletOptionRegex = try? NSRegularExpression(pattern: #"^\s*[-*•]\s*(?:\[\s*[xX ]?\s*\]\s*)?(.+)$"#)
    /// Detects checkbox-style options: "- [ ] A) ..." or "- [x] B) ..."
    static let checkboxOptionPattern = #"^\s*[-*•]\s*\[\s*[xX ]?\s*\]"#
    /// Detects multi-select markers in question text (parenthetical or inline).
    static let multiSelectPattern =
        #"(?i)(?:\(\s*)?(?:select\s+all\s+that\s+apply|select\s+multiple(?:\s+options)?|multi[-\s]?select|seleziona\s+(?:tutto(?:\s+quello\s+che\s+si\s+applica)?|multiplo|multiple|piu)(?:\s+opzioni)?)\s*(?:\))?"#
    static let numberedLineRegex = try? NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.+)$"#)
    static let bulletLineRegex = try? NSRegularExpression(pattern: #"^\s*[-*•]\s+(.+)$"#)
    static let checklistLineRegex = try? NSRegularExpression(pattern: #"^\s*[-*•]\s*\[\s*[xX ]\s*\]\s*(.+)$"#)
    static let digitsRegex = try? NSRegularExpression(pattern: #"\d+"#)
    static let fallbackNumberedRegex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s*(.+)"#)

    static let taskHeaderPatternForSignals =
        #"(?im)^(?:#{1,6}\s*)?(?:todo|to-do|tasks?|implementation\s+steps?|execution\s+steps?|next\s+steps?|checklist|action\s+items?|work\s*plan)\b"#

    static func isFenceDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    // Use a fixed locale for folding to ensure consistent matching regardless
    // of the user's system locale. The token sets include Italian words, so we
    // need deterministic ASCII folding rather than locale-dependent behavior.
    static let foldingLocale = Locale(identifier: "en")

    static func normalizeTodoText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
