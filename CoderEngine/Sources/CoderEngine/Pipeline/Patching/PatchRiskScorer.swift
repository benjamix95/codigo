import Foundation

// MARK: - RiskScoringInput

/// Input per il calcolo del risk score multi-fattore (§13.4).
public struct RiskScoringInput: Sendable, Equatable {
    public let filesChanged: Int
    public let linesChanged: Int
    public let isCoreModule: Bool
    public let productionLines: Int
    public let totalLines: Int
    public let dependentsCount: Int
    public let bugCountLast90d: Int

    public init(
        filesChanged: Int,
        linesChanged: Int,
        isCoreModule: Bool,
        productionLines: Int,
        totalLines: Int,
        dependentsCount: Int,
        bugCountLast90d: Int
    ) {
        self.filesChanged = filesChanged
        self.linesChanged = linesChanged
        self.isCoreModule = isCoreModule
        self.productionLines = productionLines
        self.totalLines = totalLines
        self.dependentsCount = dependentsCount
        self.bugCountLast90d = bugCountLast90d
    }
}

// MARK: - CoreModuleRegistry

/// Registro di moduli core che hanno peso più alto nel risk scoring (§13.4).
public struct CoreModuleRegistry: Sendable {
    private let patterns: Set<String>

    public static let `default` = CoreModuleRegistry(patterns: [
        "auth", "payment", "data", "security", "crypto",
        "database", "migration", "core", "keychain"
    ])

    public init(patterns: Set<String>) {
        self.patterns = patterns
    }

    /// Un file è "core" se il suo path contiene uno dei pattern.
    public func isCoreModule(filePath: String) -> Bool {
        let lowered = filePath.lowercased()
        return patterns.contains { lowered.contains($0) }
    }
}

// MARK: - PatchRiskScorer

/// Calcola il risk score multi-fattore per un patch-set (§13.4).
///
/// Formula:
/// ```
/// risk = (files_changed_normalized * 0.15)
///      + (lines_changed_normalized * 0.20)
///      + (core_module_weight * 0.15)
///      + (production_vs_test_ratio * 0.20)
///      + (dependents_count_normalized * 0.15)
///      + (file_bug_history_score * 0.15)
/// ```
public struct PatchRiskScorer: Sendable {

    public static let filesWeight: Double = 0.15
    public static let linesWeight: Double = 0.20
    public static let coreWeight: Double = 0.15
    public static let prodRatioWeight: Double = 0.20
    public static let dependentsWeight: Double = 0.15
    public static let bugHistoryWeight: Double = 0.15

    public init() {}

    // MARK: - Individual Factors

    /// `min(files_changed / 20, 1.0)`
    public func filesChangedNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 20.0, 1.0)
    }

    /// `min(lines_changed / 500, 1.0)`
    public func linesChangedNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 500.0, 1.0)
    }

    /// `1.0` per moduli core, `0.3` per altri.
    public func coreModuleWeight(isCoreModule: Bool) -> Double {
        isCoreModule ? 1.0 : 0.3
    }

    /// `production_lines / total_lines` — più alto = più rischioso.
    public func productionVsTestRatio(
        productionLines: Int,
        totalLines: Int
    ) -> Double {
        guard totalLines > 0 else { return 0 }
        return min(Double(max(productionLines, 0)) / Double(totalLines), 1.0)
    }

    /// `min(dependents / 10, 1.0)`
    public func dependentsNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 10.0, 1.0)
    }

    /// `min(bug_count_last_90d / 5, 1.0)`
    public func bugHistoryNormalized(_ bugCount: Int) -> Double {
        min(Double(max(bugCount, 0)) / 5.0, 1.0)
    }

    // MARK: - Composite Score

    /// Calcola il risk score aggregato da input strutturato.
    public func computeScore(from input: RiskScoringInput) -> Double {
        let f1 = filesChangedNormalized(input.filesChanged)
        let f2 = linesChangedNormalized(input.linesChanged)
        let f3 = coreModuleWeight(isCoreModule: input.isCoreModule)
        let f4 = productionVsTestRatio(
            productionLines: input.productionLines,
            totalLines: input.totalLines
        )
        let f5 = dependentsNormalized(input.dependentsCount)
        let f6 = bugHistoryNormalized(input.bugCountLast90d)

        let score = (f1 * Self.filesWeight)
            + (f2 * Self.linesWeight)
            + (f3 * Self.coreWeight)
            + (f4 * Self.prodRatioWeight)
            + (f5 * Self.dependentsWeight)
            + (f6 * Self.bugHistoryWeight)

        return min(max(score, 0), 1.0)
    }

    /// Costruisce un `RiskBreakdown` completo a partire dall'input.
    public func computeBreakdown(
        from input: RiskScoringInput
    ) -> RiskBreakdown {
        RiskBreakdown(
            filesChangedScore: filesChangedNormalized(input.filesChanged),
            linesChangedScore: linesChangedNormalized(input.linesChanged),
            coreModuleScore: coreModuleWeight(isCoreModule: input.isCoreModule),
            testVsProductionRatio: productionVsTestRatio(
                productionLines: input.productionLines,
                totalLines: input.totalLines
            ),
            dependentsCount: input.dependentsCount,
            fileBugHistoryScore: bugHistoryNormalized(input.bugCountLast90d)
        )
    }

    // MARK: - Convenience

    /// Calcola score e breakdown in un colpo solo.
    public func evaluate(
        from input: RiskScoringInput
    ) -> (score: Double, breakdown: RiskBreakdown) {
        let breakdown = computeBreakdown(from: input)
        let score = computeScore(from: input)
        return (score, breakdown)
    }

    /// Richiede review extra se risk > 0.7 (§13.4 regola).
    public func requiresExtraReview(score: Double) -> Bool {
        score > 0.7
    }
}
