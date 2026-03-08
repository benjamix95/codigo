import XCTest
@testable import CoderEngine

final class PatchManifestTests: XCTestCase {

    // MARK: - Helpers

    private func makePatch(
        touchedFiles: [String] = ["Sources/A.swift"],
        riskScore: Double = 0.42
    ) -> PatchManifest {
        PatchManifest(
            patchId: "p_001",
            jobId: "job_001",
            taskId: "T1",
            provider: "codex-cli",
            agentRole: .coder,
            touchedFiles: touchedFiles,
            unifiedDiffPath: "artifacts/patches/p_001.diff",
            riskScore: riskScore
        )
    }

    // MARK: - Coding round-trip

    func testPatchManifest_codingRoundTrip() throws {
        let patch = makePatch()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(patch)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PatchManifest.self, from: data)

        XCTAssertEqual(patch.patchId, decoded.patchId)
        XCTAssertEqual(patch.agentRole, decoded.agentRole)
        XCTAssertEqual(patch.touchedFiles, decoded.touchedFiles)
        XCTAssertEqual(patch.riskScore, decoded.riskScore)
    }

    // MARK: - Risk score

    func testPatchManifest_requiresExtraReview() {
        XCTAssertFalse(makePatch(riskScore: 0.5).requiresExtraReview)
        XCTAssertFalse(makePatch(riskScore: 0.7).requiresExtraReview)
        XCTAssertTrue(makePatch(riskScore: 0.71).requiresExtraReview)
        XCTAssertTrue(makePatch(riskScore: 1.0).requiresExtraReview)
    }

    // MARK: - Blast radius

    func testPatchManifest_blastRadius_normal() {
        let patch = makePatch(touchedFiles: Array(repeating: "f.swift", count: 5))
        XCTAssertEqual(patch.blastRadiusLevel, .normal)
    }

    func testPatchManifest_blastRadius_extraReview() {
        let patch = makePatch(touchedFiles: Array(repeating: "f.swift", count: 15))
        XCTAssertEqual(patch.blastRadiusLevel, .extraReview)
    }

    func testPatchManifest_blastRadius_manualApproval() {
        let patch = makePatch(touchedFiles: Array(repeating: "f.swift", count: 30))
        XCTAssertEqual(patch.blastRadiusLevel, .manualApproval)
    }

    // MARK: - RiskBreakdown

    func testRiskBreakdown_computeRiskScore() {
        let breakdown = RiskBreakdown(
            filesChangedScore: 0.1,
            linesChangedScore: 0.15,
            coreModuleScore: 0.05,
            testVsProductionRatio: 0.8,
            dependentsCount: 3,
            fileBugHistoryScore: 0.12
        )
        let score = breakdown.computeRiskScore()
        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThanOrEqual(score, 1)
    }

    func testRiskBreakdown_zeroValues() {
        let breakdown = RiskBreakdown()
        XCTAssertEqual(breakdown.computeRiskScore(), 0)
    }

    // MARK: - Validation

    func testPatchManifest_validationPass() throws {
        XCTAssertNoThrow(try makePatch().validate())
    }

    func testPatchManifest_emptyPatchId_fails() {
        var patch = makePatch()
        patch.patchId = ""
        XCTAssertThrowsError(try patch.validate())
    }

    func testPatchManifest_emptyTouchedFiles_fails() {
        let patch = makePatch(touchedFiles: [])
        XCTAssertThrowsError(try patch.validate())
    }

    func testPatchManifest_riskScoreOutOfRange_fails() {
        let patch = makePatch(riskScore: 1.5)
        XCTAssertThrowsError(try patch.validate())
    }

    func testPatchManifest_negativeRiskScore_fails() {
        let patch = makePatch(riskScore: -0.1)
        XCTAssertThrowsError(try patch.validate())
    }

    // MARK: - Identifiable

    func testPatchManifest_identifiable() {
        let patch = makePatch()
        XCTAssertEqual(patch.id, "p_001")
    }
}
