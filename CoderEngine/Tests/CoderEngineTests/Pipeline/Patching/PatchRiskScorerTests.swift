import XCTest
@testable import CoderEngine

final class PatchRiskScorerTests: XCTestCase {

    let scorer = PatchRiskScorer()

    // MARK: - Individual Factor Tests

    func testFilesChangedNormalized() {
        XCTAssertEqual(scorer.filesChangedNormalized(0), 0)
        XCTAssertEqual(scorer.filesChangedNormalized(10), 0.5)
        XCTAssertEqual(scorer.filesChangedNormalized(20), 1.0)
        XCTAssertEqual(scorer.filesChangedNormalized(40), 1.0, "Clamps at 1.0")
        XCTAssertEqual(scorer.filesChangedNormalized(-5), 0, "Negative treated as 0")
    }

    func testLinesChangedNormalized() {
        XCTAssertEqual(scorer.linesChangedNormalized(0), 0)
        XCTAssertEqual(scorer.linesChangedNormalized(250), 0.5)
        XCTAssertEqual(scorer.linesChangedNormalized(500), 1.0)
        XCTAssertEqual(scorer.linesChangedNormalized(1000), 1.0, "Clamps at 1.0")
    }

    func testCoreModuleWeight() {
        XCTAssertEqual(scorer.coreModuleWeight(isCoreModule: true), 1.0)
        XCTAssertEqual(scorer.coreModuleWeight(isCoreModule: false), 0.3)
    }

    func testProductionVsTestRatio() {
        XCTAssertEqual(
            scorer.productionVsTestRatio(productionLines: 80, totalLines: 100),
            0.8
        )
        XCTAssertEqual(
            scorer.productionVsTestRatio(productionLines: 0, totalLines: 100),
            0.0
        )
        XCTAssertEqual(
            scorer.productionVsTestRatio(productionLines: 50, totalLines: 0),
            0.0,
            "Zero total lines returns 0"
        )
        XCTAssertEqual(
            scorer.productionVsTestRatio(productionLines: 200, totalLines: 100),
            1.0,
            "Clamps at 1.0"
        )
    }

    func testDependentsNormalized() {
        XCTAssertEqual(scorer.dependentsNormalized(0), 0)
        XCTAssertEqual(scorer.dependentsNormalized(5), 0.5)
        XCTAssertEqual(scorer.dependentsNormalized(10), 1.0)
        XCTAssertEqual(scorer.dependentsNormalized(20), 1.0)
    }

    func testBugHistoryNormalized() {
        XCTAssertEqual(scorer.bugHistoryNormalized(0), 0)
        XCTAssertEqual(scorer.bugHistoryNormalized(3), 0.6)
        XCTAssertEqual(scorer.bugHistoryNormalized(5), 1.0)
        XCTAssertEqual(scorer.bugHistoryNormalized(10), 1.0)
    }

    // MARK: - Composite Score Tests

    func testComputeScoreAllZero() {
        let input = RiskScoringInput(
            filesChanged: 0, linesChanged: 0, isCoreModule: false,
            productionLines: 0, totalLines: 100,
            dependentsCount: 0, bugCountLast90d: 0
        )
        let score = scorer.computeScore(from: input)
        let expectedCoreContribution = 0.3 * PatchRiskScorer.coreWeight
        XCTAssertEqual(score, expectedCoreContribution, accuracy: 0.001)
    }

    func testComputeScoreAllMax() {
        let input = RiskScoringInput(
            filesChanged: 50, linesChanged: 1000, isCoreModule: true,
            productionLines: 100, totalLines: 100,
            dependentsCount: 20, bugCountLast90d: 10
        )
        let score = scorer.computeScore(from: input)
        XCTAssertEqual(score, 1.0, accuracy: 0.001, "All factors at max = 1.0")
    }

    func testHighRiskCoreModule() {
        let input = RiskScoringInput(
            filesChanged: 2, linesChanged: 10, isCoreModule: true,
            productionLines: 10, totalLines: 10,
            dependentsCount: 12, bugCountLast90d: 5
        )
        let score = scorer.computeScore(from: input)
        XCTAssertGreaterThan(score, 0.5, "Core module with many dependents and bugs should be high risk")
    }

    func testLowRiskTestFiles() {
        let input = RiskScoringInput(
            filesChanged: 10, linesChanged: 200, isCoreModule: false,
            productionLines: 0, totalLines: 200,
            dependentsCount: 0, bugCountLast90d: 0
        )
        let score = scorer.computeScore(from: input)
        XCTAssertLessThan(score, 0.3, "Pure test files with no dependents should be low risk")
    }

    func testSpecExampleCoreVsTest() {
        let coreInput = RiskScoringInput(
            filesChanged: 1, linesChanged: 2, isCoreModule: true,
            productionLines: 2, totalLines: 2,
            dependentsCount: 12, bugCountLast90d: 5
        )
        let testInput = RiskScoringInput(
            filesChanged: 5, linesChanged: 200, isCoreModule: false,
            productionLines: 0, totalLines: 200,
            dependentsCount: 0, bugCountLast90d: 0
        )
        let coreScore = scorer.computeScore(from: coreInput)
        let testScore = scorer.computeScore(from: testInput)
        XCTAssertGreaterThan(
            coreScore, testScore,
            "2 lines in AuthManager (core, 5 bugs, 12 deps) MUST be higher risk than 200 test lines"
        )
    }

    // MARK: - Breakdown Tests

    func testComputeBreakdown() {
        let input = RiskScoringInput(
            filesChanged: 10, linesChanged: 250, isCoreModule: true,
            productionLines: 80, totalLines: 100,
            dependentsCount: 5, bugCountLast90d: 3
        )
        let breakdown = scorer.computeBreakdown(from: input)
        XCTAssertEqual(breakdown.filesChangedScore, 0.5, accuracy: 0.001)
        XCTAssertEqual(breakdown.linesChangedScore, 0.5, accuracy: 0.001)
        XCTAssertEqual(breakdown.coreModuleScore, 1.0, accuracy: 0.001)
        XCTAssertEqual(breakdown.testVsProductionRatio, 0.8, accuracy: 0.001)
        XCTAssertEqual(breakdown.dependentsCount, 5)
        XCTAssertEqual(breakdown.fileBugHistoryScore, 0.6, accuracy: 0.001)
    }

    func testEvaluateReturnsScoreAndBreakdown() {
        let input = RiskScoringInput(
            filesChanged: 5, linesChanged: 100, isCoreModule: false,
            productionLines: 50, totalLines: 100,
            dependentsCount: 2, bugCountLast90d: 1
        )
        let (score, breakdown) = scorer.evaluate(from: input)
        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThanOrEqual(score, 1.0)
        XCTAssertEqual(breakdown.filesChangedScore, 0.25, accuracy: 0.001)
    }

    // MARK: - Extra Review Threshold

    func testRequiresExtraReview() {
        XCTAssertFalse(scorer.requiresExtraReview(score: 0.5))
        XCTAssertFalse(scorer.requiresExtraReview(score: 0.7))
        XCTAssertTrue(scorer.requiresExtraReview(score: 0.71))
        XCTAssertTrue(scorer.requiresExtraReview(score: 1.0))
    }

    // MARK: - CoreModuleRegistry Tests

    func testCoreModuleRegistryDefault() {
        let registry = CoreModuleRegistry.default
        XCTAssertTrue(registry.isCoreModule(filePath: "Sources/Auth/AuthManager.swift"))
        XCTAssertTrue(registry.isCoreModule(filePath: "Payment/PaymentService.swift"))
        XCTAssertTrue(registry.isCoreModule(filePath: "Core/Database/Schema.swift"))
        XCTAssertFalse(registry.isCoreModule(filePath: "UI/Views/HomeView.swift"))
        XCTAssertFalse(registry.isCoreModule(filePath: "Tests/SomeTest.swift"))
    }

    func testCoreModuleRegistryCustom() {
        let custom = CoreModuleRegistry(patterns: ["billing", "api"])
        XCTAssertTrue(custom.isCoreModule(filePath: "Services/Billing/Invoice.swift"))
        XCTAssertTrue(custom.isCoreModule(filePath: "API/Router.swift"))
        XCTAssertFalse(custom.isCoreModule(filePath: "UI/Dashboard.swift"))
    }

    // MARK: - Weight Sum Verification

    func testWeightsSumToOne() {
        let sum = PatchRiskScorer.filesWeight
            + PatchRiskScorer.linesWeight
            + PatchRiskScorer.coreWeight
            + PatchRiskScorer.prodRatioWeight
            + PatchRiskScorer.dependentsWeight
            + PatchRiskScorer.bugHistoryWeight
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "All weights must sum to 1.0")
    }
}
