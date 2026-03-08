import Foundation

// MARK: - PatchRiskInput

/// Input per il calcolo del risk score multi-fattore (§13.4).
public struct PatchRiskInput: Sendable, Equatable {
    public let filesChanged: Int
    public let linesChanged: Int
    public let isCoreModule: Bool
    public let productionLines: Int
    public let testLines: Int
    public let dependentsCount: Int
    public let bugCountLast90d: Int

    public init(
        filesChanged: Int,
        linesChanged: Int,
        isCoreModule: Bool = false,
        productionLines: Int = 0,
        testLines: Int = 0,
        dependentsCount: Int = 0,
        bugCountLast90d: Int = 0
    ) {
        self.filesChanged = filesChanged
        self.linesChanged = linesChanged
        self.isCoreModule = isCoreModule
        self.productionLines = productionLines
        self.testLines = testLines
        self.dependentsCount = dependentsCount
        self.bugCountLast90d = bugCountLast90d
    }
}

// MARK: - PatchRiskScorer

/// Calcola il risk score per una patch usando 6 fattori pesati (§13.4).
///
/// Formula:
/// ```
/// risk = files_changed_normalized   * 0.15
///      + lines_changed_normalized   * 0.20
///      + core_module_weight         * 0.15
///      + production_vs_test_ratio   * 0.20
///      + dependents_count_norm      * 0.15
///      + file_bug_history_score     * 0.15
/// ```
public struct PatchRiskScorer: Sendable {

    /// Soglia core module: moduli "auth, payment, data" pesano 1.0, altri 0.3
    public static let coreModuleWeight: Double = 1.0
    public static let nonCoreModuleWeight: Double = 0.3

    /// Soglia risk alto (§13.4 regola): patch > 0.7 richiede review extra
    public static let highRiskThreshold: Double = 0.7

    public init() {}

    // MARK: - Score Calculation

    /// Calcola il risk score aggregato da un input strutturato.
    public func score(from input: PatchRiskInput) -> Double {
        let breakdown = computeBreakdown(from: input)
        return breakdown.computeRiskScore()
    }

    /// Calcola il breakdown dettagliato dei 6 fattori.
    public func computeBreakdown(from input: PatchRiskInput) -> RiskBreakdown {
        RiskBreakdown(
            filesChangedScore: filesChangedNormalized(input.filesChanged),
            linesChangedScore: linesChangedNormalized(input.linesChanged),
            coreModuleScore: coreModuleScore(input.isCoreModule),
            testVsProductionRatio: productionVsTestRatio(
                production: input.productionLines,
                test: input.testLines
            ),
            dependentsCount: input.dependentsCount,
            fileBugHistoryScore: fileBugHistoryScore(input.bugCountLast90d)
        )
    }

    /// Calcola il risk score da un `PatchManifest` + informazioni contestuali.
    public func score(
        manifest: PatchManifest,
        linesChanged: Int,
        isCoreModule: Bool,
        productionLines: Int,
        testLines: Int,
        dependentsCount: Int,
        bugCountLast90d: Int
    ) -> Double {
        let input = PatchRiskInput(
            filesChanged: manifest.touchedFiles.count,
            linesChanged: linesChanged,
            isCoreModule: isCoreModule,
            productionLines: productionLines,
            testLines: testLines,
            dependentsCount: dependentsCount,
            bugCountLast90d: bugCountLast90d
        )
        return score(from: input)
    }

    /// Verifica se il risk score supera la soglia alta (§13.4).
    public func requiresExtraReview(_ riskScore: Double) -> Bool {
        riskScore > Self.highRiskThreshold
    }

    // MARK: - Normalizzazione singoli fattori

    /// `min(files_changed / 20, 1.0)` (§13.4.1)
    public func filesChangedNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 20.0, 1.0)
    }

    /// `min(lines_changed / 500, 1.0)` (§13.4.2)
    public func linesChangedNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 500.0, 1.0)
    }

    /// `1.0` per core module, `0.3` per altri (§13.4.3)
    public func coreModuleScore(_ isCore: Bool) -> Double {
        isCore ? Self.coreModuleWeight : Self.nonCoreModuleWeight
    }

    /// `production_lines / total_lines` (§13.4.4). Se total=0, ritorna 0.
    public func productionVsTestRatio(production: Int, test: Int) -> Double {
        let total = production + test
        guard total > 0 else { return 0 }
        return Double(production) / Double(total)
    }

    /// `min(dependents / 10, 1.0)` (§13.4.5)
    public func dependentsCountNormalized(_ count: Int) -> Double {
        min(Double(max(count, 0)) / 10.0, 1.0)
    }

    /// `min(bug_count_last_90d / 5, 1.0)` (§13.4.6)
    public func fileBugHistoryScore(_ bugCount: Int) -> Double {
        min(Double(max(bugCount, 0)) / 5.0, 1.0)
    }
}
