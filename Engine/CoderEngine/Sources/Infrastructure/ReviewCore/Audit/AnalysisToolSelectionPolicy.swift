import Foundation

// MARK: - AnalysisToolSelectionPolicy

/// Policy che determina quali audit tool includere in un'analisi.
///
/// Quando l'utente richiede un'analisi generica ("analizza l'app", "fai un audit completo"),
/// il sistema usa questa policy per selezionare automaticamente i tool appropriati,
/// **includendo i performance tool** senza richiesta esplicita.
///
/// Quando l'utente chiede esplicitamente un tool specifico, la policy non interviene
/// e il tool viene eseguito singolarmente.
public enum AnalysisToolSelectionPolicy {

    /// Modalità di selezione tool per l'analisi.
    public enum SelectionMode: String, Sendable {
        /// Analisi completa: include tutti i tool (security + bug + performance + meta).
        case full
        /// Solo security e bug — esclude performance.
        case securityAndBugs
        /// Solo performance.
        case performanceOnly
        /// Tool singolo esplicito.
        case explicit
    }

    // MARK: - Tool Selection

    /// Seleziona i tool da eseguire in base al prompt utente e al contesto.
    ///
    /// - Parameters:
    ///   - userPrompt: Il testo del prompt utente (normalizzato lowercase).
    ///   - explicitToolName: Nome tool esplicito se l'utente l'ha specificato.
    /// - Returns: La modalità di selezione e i tool names da eseguire.
    public static func resolveToolSelection(
        userPrompt: String,
        explicitToolName: String? = nil
    ) -> (mode: SelectionMode, toolNames: [String]) {
        // Tool esplicito: esegui solo quello
        if let explicit = explicitToolName,
           ReviewAuditToolName.allToolNames.contains(explicit) {
            return (.explicit, [explicit])
        }

        let lower = userPrompt.lowercased()

        // Richiesta performance esplicita
        if isExplicitPerformanceRequest(lower) {
            return (.performanceOnly, ReviewAuditToolName.performanceTools)
        }

        // Analisi completa (default per prompt generici)
        if isFullAnalysisRequest(lower) {
            return (.full, ReviewAuditToolName.all)
        }

        // Richiesta security/bug specifica
        if isSecurityOrBugRequest(lower) {
            return (.securityAndBugs, ReviewAuditToolName.securityTools + ReviewAuditToolName.bugTools)
        }

        // Default: analisi completa (include performance)
        return (.full, ReviewAuditToolName.all)
    }

    /// Determina il profilo audit da usare per `audit_run_profile`.
    public static func resolveProfile(
        userPrompt: String,
        explicitProfile: ReviewAuditProfile? = nil
    ) -> ReviewAuditProfile {
        if let explicit = explicitProfile { return explicit }

        let lower = userPrompt.lowercased()
        if isExplicitPerformanceRequest(lower) { return .performanceDeep }
        if lower.contains("ios") || lower.contains("app store") { return .iosPreflight }
        if lower.contains("security") || lower.contains("sicurezza") { return .securityDeep }
        if lower.contains("bug") || lower.contains("regressione") { return .bugHuntDeep }
        if lower.contains("release") || lower.contains("deploy") { return .releaseGate }
        if lower.contains("backend") || lower.contains("api") { return .backendRegression }
        return .quick
    }

    /// Restituisce true se i tool performance devono essere inclusi nel flusso corrente.
    public static func shouldIncludePerformanceTools(
        mode: SelectionMode
    ) -> Bool {
        switch mode {
        case .full, .performanceOnly:
            return true
        case .securityAndBugs, .explicit:
            return false
        }
    }

    // MARK: - Private Helpers

    private static func isExplicitPerformanceRequest(_ lower: String) -> Bool {
        let keywords = [
            "performance", "prestazioni", "benchmark", "bottleneck",
            "collo di bottiglia", "hot path", "profiling", "startup time",
            "memoria", "memory leak", "retain cycle", "responsività",
        ]
        return keywords.contains { lower.contains($0) }
    }

    private static func isFullAnalysisRequest(_ lower: String) -> Bool {
        let keywords = [
            "analizza", "analisi completa", "audit completo", "audit",
            "controlla tutto", "verifica tutto", "scan completo",
            "trova problemi", "trova bug", "check everything",
        ]
        return keywords.contains { lower.contains($0) }
    }

    private static func isSecurityOrBugRequest(_ lower: String) -> Bool {
        let keywords = [
            "sicurezza", "security", "vulnerabilit",
            "bug", "errore", "crash", "fix",
        ]
        return keywords.contains { lower.contains($0) }
    }
}
