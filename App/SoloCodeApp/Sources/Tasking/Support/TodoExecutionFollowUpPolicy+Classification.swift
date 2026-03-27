import Foundation

extension TodoExecutionFollowUpPolicy {
    enum ExecutionTitleKind {
        case invalidPlaceholder
        case analysis
        case implementation
        case validation
        case documentation
        case generic
    }

    static func sanitizeMeaningfulExecutionTitles(_ titles: [String]) -> [String] {
        var seenKeys = Set<String>()
        var sanitized: [String] = []

        for raw in titles {
            guard let trimmed = meaningfulExecutionTitle(from: raw) else { continue }
            let key = normalizedTitleKey(trimmed)
            guard seenKeys.insert(key).inserted else { continue }
            sanitized.append(trimmed)
        }

        return sanitized
    }

    static func meaningfulExecutionTitle(from rawTitle: String) -> String? {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !isExecutionFollowUpTitle(trimmed) else { return nil }
        guard classifyTitle(trimmed) != .invalidPlaceholder else { return nil }
        return trimmed
    }

    static func expandedSequenceIfNeeded(for title: String) -> [String]? {
        switch classifyTitle(title) {
        case .analysis:
            return [
                scopeTitle,
                title,
                findingsConsolidationTitle,
            ]
        case .implementation:
            return [
                targetAnalysisTitle,
                title,
            ]
        default:
            return nil
        }
    }

    static func appendMissingFinalFollowUps(to titles: [String]) -> [String] {
        let executableTitles = titles.filter { !isExecutionFollowUpTitle($0) }
        guard !executableTitles.isEmpty else { return [] }

        var ordered = sanitizeMeaningfulExecutionTitles(titles)
        for followUpTitle in finalFollowUpTitles(forExecutableTitles: executableTitles) {
            let key = normalizedTitleKey(followUpTitle)
            if !ordered.contains(where: { normalizedTitleKey($0) == key }) {
                ordered.append(followUpTitle)
            }
        }
        return ordered
    }

    static func finalFollowUpTitles(forExecutableTitles titles: [String]) -> [String] {
        let meaningfulTitles = sanitizeMeaningfulExecutionTitles(titles)
        guard !meaningfulTitles.isEmpty else { return [] }

        var followUps: [String] = []
        if shouldRequireReviewFollowUp(forExecutableTitles: meaningfulTitles) {
            followUps.append(reviewTitle)
        }
        if shouldRequireDocWriterFollowUp(forExecutableTitles: meaningfulTitles) {
            followUps.append(docWriterTitle)
        }
        return followUps
    }

    static func shouldRequireReviewFollowUp(forExecutableTitles titles: [String]) -> Bool {
        sanitizeMeaningfulExecutionTitles(titles).contains {
            classifyTitle($0) == .implementation
        }
    }

    static func shouldRequireDocWriterFollowUp(forExecutableTitles titles: [String]) -> Bool {
        let meaningfulTitles = sanitizeMeaningfulExecutionTitles(titles)
        guard !meaningfulTitles.isEmpty else { return false }
        return meaningfulTitles.count >= 2 || shouldRequireReviewFollowUp(forExecutableTitles: meaningfulTitles)
    }

    static func classifyTitle(_ title: String) -> ExecutionTitleKind {
        let normalized = normalizedTitleKey(title)
        guard !normalized.isEmpty else { return .invalidPlaceholder }
        if isPlaceholderTitle(normalized) {
            return .invalidPlaceholder
        }
        if matchesAnySignal(in: normalized, signals: implementationSignals) {
            return .implementation
        }
        if matchesAnySignal(in: normalized, signals: analysisSignals) {
            return .analysis
        }
        if matchesAnySignal(in: normalized, signals: validationSignals) {
            return .validation
        }
        if matchesAnySignal(in: normalized, signals: documentationSignals) {
            return .documentation
        }
        return .generic
    }

    static func isPlaceholderTitle(_ normalizedTitle: String) -> Bool {
        let exactPlaceholders: Set<String> = [
            "task",
            "tasks",
            "todo",
            "to do",
            "step",
            "steps",
            "phase",
            "fase",
            "analysis",
            "analisi",
            "setup",
            "preparazione",
            "implementation",
            "implementazione",
        ]
        if exactPlaceholders.contains(normalizedTitle) {
            return true
        }

        let placeholderPatterns = [
            #"^(task|tasks|step|steps|phase|fase)\s+\d+$"#,
            #"^(step|fase|phase)\s+[a-z0-9]+$"#,
        ]
        return placeholderPatterns.contains {
            normalizedTitle.range(of: $0, options: .regularExpression) != nil
        }
    }

    static func matchesAnySignal(in normalizedTitle: String, signals: [String]) -> Bool {
        signals.contains { normalizedTitle.contains($0) }
    }

    static let implementationSignals = [
        "implement",
        "fix",
        "refactor",
        "update",
        "modify",
        "edit",
        "patch",
        "add",
        "remove",
        "delete",
        "rename",
        "replace",
        "create file",
        "split",
        "migrate",
        "wire",
        "integrate",
        "write code",
        "correggere",
        "implementare",
        "rifattorizzare",
        "aggiornare",
        "modificare",
        "editare",
        "aggiungere",
        "rimuovere",
        "eliminare",
        "rinominare",
        "sostituire",
        "creare file",
        "dividere",
        "migrare",
        "collegare",
        "integrare",
    ]

    static let analysisSignals = [
        "scan",
        "audit",
        "analy",
        "inspect",
        "investig",
        "explor",
        "review",
        "map",
        "assess",
        "read",
        "grep",
        "trace",
        "scansion",
        "analizz",
        "ispezion",
        "indag",
        "esplor",
        "mapp",
        "valut",
        "leggere",
        "traccia",
    ]

    static let validationSignals = [
        "test",
        "verify",
        "validat",
        "smoke",
        "benchmark",
        "qa",
        "lint",
        "typecheck",
        "verific",
        "convalid",
        "prestaz",
    ]

    static let documentationSignals = [
        "document",
        "report",
        "summary",
        "summar",
        "changelog",
        "writeup",
        "resoconto",
        "documentare",
    ]
}
