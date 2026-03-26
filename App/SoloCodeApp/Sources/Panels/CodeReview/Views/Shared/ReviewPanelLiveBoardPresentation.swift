import CoderEngine
import Foundation

/// Titoli e sottotitoli del Live Board coerenti con scope e profili selezionati nel panel.
enum ReviewPanelLiveBoardPresentation {
    static func boardHeaderTitle(isRunning: Bool, modes: Set<CodeReviewPanelMode>, scope: ReviewSessionScope?) -> String {
        let scan = scanLabel(modes: modes)
        let scopeBit = scope.map { shortScopeLabel($0) } ?? "scope"
        if isRunning {
            return "\(scan) — \(scopeBit)"
        }
        return "Run completata — \(scan)"
    }

    static func boardSubtitle(isRunning: Bool, modes: Set<CodeReviewPanelMode>) -> String {
        let scan = scanLabel(modes: modes)
        if isRunning {
            return "Profilo: \(scan). File e worker aggiornati mentre la sessione evolve."
        }
        return "Riepilogo dell’ultima sessione con profilo \(scan)."
    }

    static func pipelineCardTitle(
        modes: Set<CodeReviewPanelMode>,
        scanDepth: ReviewScanDepth? = nil
    ) -> String {
        let base = "Avanzamento — \(scanLabel(modes: modes))"
        guard let scanDepth else { return base }
        return "\(base) · \(scanDepth.displayName)"
    }

    private static func scanLabel(modes: Set<CodeReviewPanelMode>) -> String {
        let ordered: [CodeReviewPanelMode] = [.standard, .securityAudit, .bugFinder]
        let active = ordered.filter { modes.contains($0) }
        if active.isEmpty {
            return CodeReviewPanelMode.standard.rawValue
        }
        if active.count == ordered.count {
            return "Standard + Security + Bug"
        }
        return active.map(\.rawValue).joined(separator: " · ")
    }

    private static func shortScopeLabel(_ scope: ReviewSessionScope) -> String {
        switch scope.type {
        case .uncommitted: return "non committato"
        case .staged: return "staging"
        case .workspace: return "workspace"
        case .codebase: return "codebase"
        case .againstRef: return "vs \(scope.ref ?? "ref")"
        }
    }
}

extension ReviewPipelineJobState {
    /// Avanzamento anello = solo `progressPercent` dal motore (0…100). Non usiamo più un pavimento
    /// tipo “fase 1/6 ⇒ 16%”: confondeva (alla riapertura sembrava già partito) e non ripartiva “da zero” per fase.
    var displayProgressPercent: Int {
        min(100, max(0, progressPercent))
    }

    var displayProgressText: String { "\(displayProgressPercent)%" }

    func replacingTitle(_ newTitle: String) -> ReviewPipelineJobState {
        ReviewPipelineJobState(
            title: newTitle,
            phase: phase,
            progressPercent: progressPercent,
            stepsCompleted: stepsCompleted,
            stepsTotal: stepsTotal,
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            toolsRunning: toolsRunning,
            candidateCount: candidateCount,
            verifiedCount: verifiedCount,
            publishedFindingCount: publishedFindingCount,
            hiddenFindingCount: hiddenFindingCount,
            gates: gates,
            tools: tools,
            phaseLedger: phaseLedger,
            bundleModes: bundleModes,
            isTerminal: isTerminal
        )
    }
}
