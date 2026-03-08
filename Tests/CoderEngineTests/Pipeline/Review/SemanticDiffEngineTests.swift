import XCTest
@testable import CoderEngine

final class SemanticDiffEngineTests: XCTestCase {

    private let engine = SemanticDiffEngine()

    private func makeChange(
        type: SemanticChangeType = .functionBodyChanged,
        impact: SemanticImpact = .behaviorChange,
        file: String = "Test.swift"
    ) -> SemanticChange {
        SemanticChange(
            type: type,
            symbol: "func test()",
            file: file,
            impact: impact
        )
    }

    // MARK: - Report Generation

    func testGenerateReport_correctId() {
        let report = engine.generateReport(
            taskId: "T1", patchId: "p_abc12345",
            changes: []
        )
        XCTAssertEqual(report.semanticDiffId, "sdiff_p_abc123")
        XCTAssertEqual(report.taskId, "T1")
        XCTAssertEqual(report.patchId, "p_abc12345")
    }

    func testGenerateReport_computesSummary() {
        let changes = [
            makeChange(impact: .breakingChange),
            makeChange(impact: .behaviorChange),
            makeChange(impact: .cosmetic),
            makeChange(impact: .dependencyChange),
        ]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        XCTAssertEqual(report.summary.breakingChanges, 1)
        XCTAssertEqual(report.summary.behaviorChanges, 1)
        XCTAssertEqual(report.summary.cosmeticChanges, 1)
        XCTAssertEqual(report.summary.dependencyChanges, 1)
        XCTAssertEqual(report.summary.totalSemanticChanges, 4)
    }

    func testGenerateReport_emptyChanges() {
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: []
        )
        XCTAssertEqual(report.summary.totalSemanticChanges, 0)
    }

    // MARK: - hasBreakingChanges

    func testHasBreakingChanges_true() {
        let changes = [makeChange(impact: .breakingChange)]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        XCTAssertTrue(report.hasBreakingChanges)
    }

    func testHasBreakingChanges_false() {
        let changes = [makeChange(impact: .cosmetic)]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        XCTAssertFalse(report.hasBreakingChanges)
    }

    // MARK: - Non-Cosmetic Filter

    func testNonCosmeticChanges_filtersCosmetic() {
        let changes = [
            makeChange(impact: .breakingChange),
            makeChange(impact: .cosmetic),
            makeChange(impact: .cosmetic),
        ]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        XCTAssertEqual(report.nonCosmeticChanges.count, 1)
    }

    // MARK: - Classify Signature Change

    func testClassifySignature_public_isBreaking() {
        let change = engine.classifySignatureChange(
            symbol: "foo()", file: "A.swift",
            oldSignature: "func foo()",
            newSignature: "func foo(x: Int)",
            isPublic: true
        )
        XCTAssertEqual(change.impact, .breakingChange)
        XCTAssertEqual(change.type, .functionSignatureChanged)
    }

    func testClassifySignature_private_isBehavior() {
        let change = engine.classifySignatureChange(
            symbol: "bar()", file: "A.swift",
            oldSignature: "func bar()",
            newSignature: "func bar(x: Int)",
            isPublic: false
        )
        XCTAssertEqual(change.impact, .behaviorChange)
    }

    // MARK: - Classify Import Change

    func testClassifyImport_added() {
        let change = engine.classifyImportChange(
            file: "A.swift", module: "FoundationNetworking",
            added: true
        )
        XCTAssertEqual(change.type, .importAdded)
        XCTAssertEqual(change.impact, .dependencyChange)
    }

    func testClassifyImport_removed() {
        let change = engine.classifyImportChange(
            file: "A.swift", module: "OldLib",
            added: false
        )
        XCTAssertEqual(change.type, .importRemoved)
    }

    // MARK: - Filter Cosmetic Changes

    func testFilterCosmeticChanges_removesCosmetic() {
        let changes = [
            makeChange(impact: .cosmetic),
            makeChange(impact: .breakingChange),
        ]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        let filtered = engine.filterCosmeticChanges(from: report)
        XCTAssertEqual(filtered.changes.count, 1)
        XCTAssertEqual(
            filtered.summary.totalSemanticChanges, 1
        )
    }

    // MARK: - Extract Breaking Changes

    func testExtractBreakingChanges() {
        let changes = [
            makeChange(impact: .breakingChange),
            makeChange(impact: .behaviorChange),
            makeChange(impact: .breakingChange),
        ]
        let report = engine.generateReport(
            taskId: "T1", patchId: "p1", changes: changes
        )
        let breaking = engine.extractBreakingChanges(from: report)
        XCTAssertEqual(breaking.count, 2)
    }

    // MARK: - SemanticDiffReport Codable

    func testSemanticDiffReport_roundTrip() throws {
        let report = SemanticDiffReport(
            semanticDiffId: "sdiff_1",
            taskId: "T1",
            patchId: "p1",
            changes: [makeChange()]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(
            SemanticDiffReport.self, from: data
        )
        XCTAssertEqual(report, decoded)
    }

    // MARK: - SemanticChangeType

    func testSemanticChangeType_allCases() {
        XCTAssertEqual(SemanticChangeType.allCases.count, 11)
    }

    func testSemanticImpact_allCases() {
        XCTAssertEqual(SemanticImpact.allCases.count, 4)
    }
}
