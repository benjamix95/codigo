import XCTest
@testable import CoderEngine

final class PatchRiskScorerTests: XCTestCase {

    private let scorer = PatchRiskScorer()

    // MARK: - filesChangedNormalized

    func testFilesChangedNormalized_zero() {
        XCTAssertEqual(scorer.filesChangedNormalized(0), 0)
    }

    func testFilesChangedNormalized_belowCap() {
        XCTAssertEqual(scorer.filesChangedNormalized(10), 0.5)
    }

    func testFilesChangedNormalized_atCap() {
        XCTAssertEqual(scorer.filesChangedNormalized(20), 1.0)
    }

    func testFilesChangedNormalized_aboveCap() {
        XCTAssertEqual(scorer.filesChangedNormalized(40), 1.0)
    }

    func testFilesChangedNormalized_negative() {
        XCTAssertEqual(scorer.filesChangedNormalized(-5), 0)
    }

    // MARK: - linesChangedNormalized

    func testLinesChangedNormalized_belowCap() {
        XCTAssertEqual(scorer.linesChangedNormalized(250), 0.5)
    }

    func testLinesChangedNormalized_atCap() {
        XCTAssertEqual(scorer.linesChangedNormalized(500), 1.0)
    }

    func testLinesChangedNormalized_aboveCap() {
        XCTAssertEqual(scorer.linesChangedNormalized(1000), 1.0)
    }

    // MARK: - coreModuleScore

    func testCoreModuleScore_core() {
        XCTAssertEqual(scorer.coreModuleScore(true), 1.0)
    }

    func testCoreModuleScore_nonCore() {
        XCTAssertEqual(scorer.coreModuleScore(false), 0.3)
    }

    // MARK: - productionVsTestRatio

    func testProductionVsTestRatio_allProduction() {
        XCTAssertEqual(
            scorer.productionVsTestRatio(production: 100, test: 0),
            1.0
        )
    }

    func testProductionVsTestRatio_allTest() {
        XCTAssertEqual(
            scorer.productionVsTestRatio(production: 0, test: 100),
            0.0
        )
    }

    func testProductionVsTestRatio_mixed() {
        XCTAssertEqual(
            scorer.productionVsTestRatio(production: 60, test: 40),
            0.6
        )
    }

    func testProductionVsTestRatio_zeroTotal() {
        XCTAssertEqual(
            scorer.productionVsTestRatio(production: 0, test: 0),
            0.0
        )
    }

    // MARK: - dependentsCountNormalized

    func testDependentsNormalized_belowCap() {
        XCTAssertEqual(scorer.dependentsCountNormalized(5), 0.5)
    }

    func testDependentsNormalized_atCap() {
        XCTAssertEqual(scorer.dependentsCountNormalized(10), 1.0)
    }

    // MARK: - fileBugHistoryScore

    func testBugHistoryScore_zero() {
        XCTAssertEqual(scorer.fileBugHistoryScore(0), 0)
    }

    func testBugHistoryScore_atCap() {
        XCTAssertEqual(scorer.fileBugHistoryScore(5), 1.0)
    }

    func testBugHistoryScore_aboveCap() {
        XCTAssertEqual(scorer.fileBugHistoryScore(10), 1.0)
    }

    // MARK: - score aggregato

    func testScore_allZero() {
        let input = PatchRiskInput(filesChanged: 0, linesChanged: 0)
        let score = scorer.score(from: input)
        // core_module_score(false) = 0.3, tutto il resto 0
        // 0.3 * 0.15 = 0.045
        XCTAssertEqual(score, 0.045, accuracy: 0.001)
    }

    func testScore_allMax() {
        let input = PatchRiskInput(
            filesChanged: 30,
            linesChanged: 600,
            isCoreModule: true,
            productionLines: 100,
            testLines: 0,
            dependentsCount: 15,
            bugCountLast90d: 10
        )
        let score = scorer.score(from: input)
        // Tutti i fattori a 1.0: 0.15 + 0.20 + 0.15 + 0.20 + 0.15 + 0.15 = 1.0
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testScore_highRiskAuthModule() {
        let input = PatchRiskInput(
            filesChanged: 2,
            linesChanged: 10,
            isCoreModule: true,
            productionLines: 10,
            testLines: 0,
            dependentsCount: 12,
            bugCountLast90d: 5
        )
        let score = scorer.score(from: input)
        // files: 2/20=0.1, lines: 10/500=0.02, core:1.0, prod:1.0, deps:1.0, bugs:1.0
        // 0.1*0.15 + 0.02*0.20 + 1.0*0.15 + 1.0*0.20 + 1.0*0.15 + 1.0*0.15
        // = 0.015 + 0.004 + 0.15 + 0.20 + 0.15 + 0.15 = 0.669
        XCTAssertEqual(score, 0.669, accuracy: 0.001)
    }

    func testScore_lowRiskTestOnly() {
        let input = PatchRiskInput(
            filesChanged: 1,
            linesChanged: 200,
            isCoreModule: false,
            productionLines: 0,
            testLines: 200,
            dependentsCount: 0,
            bugCountLast90d: 0
        )
        let score = scorer.score(from: input)
        // files: 1/20=0.05, lines: 200/500=0.4, core:0.3, prod:0.0, deps:0.0, bugs:0.0
        // 0.05*0.15 + 0.4*0.20 + 0.3*0.15 + 0.0*0.20 + 0.0*0.15 + 0.0*0.15
        // = 0.0075 + 0.08 + 0.045 + 0 + 0 + 0 = 0.1325
        XCTAssertEqual(score, 0.1325, accuracy: 0.001)
    }

    // MARK: - requiresExtraReview

    func testRequiresExtraReview_belowThreshold() {
        XCTAssertFalse(scorer.requiresExtraReview(0.7))
    }

    func testRequiresExtraReview_aboveThreshold() {
        XCTAssertTrue(scorer.requiresExtraReview(0.71))
    }

    // MARK: - computeBreakdown

    func testComputeBreakdown_returnsCorrectValues() {
        let input = PatchRiskInput(
            filesChanged: 10,
            linesChanged: 250,
            isCoreModule: true,
            productionLines: 80,
            testLines: 20,
            dependentsCount: 5,
            bugCountLast90d: 3
        )
        let breakdown = scorer.computeBreakdown(from: input)
        XCTAssertEqual(breakdown.filesChangedScore, 0.5)
        XCTAssertEqual(breakdown.linesChangedScore, 0.5)
        XCTAssertEqual(breakdown.coreModuleScore, 1.0)
        XCTAssertEqual(breakdown.testVsProductionRatio, 0.8)
        XCTAssertEqual(breakdown.dependentsCount, 5)
        XCTAssertEqual(breakdown.fileBugHistoryScore, 0.6)
    }

    // MARK: - score from manifest

    func testScoreFromManifest() {
        let manifest = PatchManifest(
            patchId: "p1",
            jobId: "j1",
            taskId: "t1",
            provider: "gpt",
            agentRole: .coder,
            touchedFiles: ["a.swift", "b.swift", "c.swift"],
            unifiedDiffPath: "diff.patch"
        )
        let score = scorer.score(
            manifest: manifest,
            linesChanged: 100,
            isCoreModule: false,
            productionLines: 100,
            testLines: 0,
            dependentsCount: 2,
            bugCountLast90d: 1
        )
        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
}
