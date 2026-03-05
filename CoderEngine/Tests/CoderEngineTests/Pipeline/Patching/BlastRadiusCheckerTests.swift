import XCTest
@testable import CoderEngine

final class BlastRadiusCheckerTests: XCTestCase {

    private let checker = BlastRadiusChecker()

    private func makePatch(files: [String]) -> PatchManifest {
        PatchManifest(
            patchId: "p_\(UUID().uuidString.prefix(4))",
            jobId: "j1",
            taskId: "t1",
            provider: "test",
            agentRole: .coder,
            touchedFiles: files,
            unifiedDiffPath: "diff.patch"
        )
    }

    // MARK: - Single patch

    func testNormalBlastRadius() {
        let patch = makePatch(files: Array(1...5).map { "f\($0).swift" })
        let result = checker.check(patch: patch)

        XCTAssertEqual(result.totalUniqueFiles, 5)
        XCTAssertEqual(result.level, .normal)
        XCTAssertFalse(result.requiresExtraReview)
        XCTAssertFalse(result.requiresManualApproval)
    }

    func testExtraReviewThreshold() {
        let patch = makePatch(files: Array(1...13).map { "f\($0).swift" })
        let result = checker.check(patch: patch)

        XCTAssertEqual(result.totalUniqueFiles, 13)
        XCTAssertEqual(result.level, .extraReview)
        XCTAssertTrue(result.requiresExtraReview)
        XCTAssertFalse(result.requiresManualApproval)
    }

    func testManualApprovalThreshold() {
        let patch = makePatch(files: Array(1...26).map { "f\($0).swift" })
        let result = checker.check(patch: patch)

        XCTAssertEqual(result.totalUniqueFiles, 26)
        XCTAssertEqual(result.level, .manualApproval)
        XCTAssertTrue(result.requiresExtraReview)
        XCTAssertTrue(result.requiresManualApproval)
    }

    func testBoundary_exactly12() {
        let patch = makePatch(files: Array(1...12).map { "f\($0).swift" })
        let result = checker.check(patch: patch)
        XCTAssertEqual(result.level, .normal)
    }

    func testBoundary_exactly25() {
        let patch = makePatch(files: Array(1...25).map { "f\($0).swift" })
        let result = checker.check(patch: patch)
        XCTAssertEqual(result.level, .extraReview)
    }

    // MARK: - Multiple patches (deduplication)

    func testMultiplePatches_deduplicateFiles() {
        let p1 = makePatch(files: ["a.swift", "b.swift", "c.swift"])
        let p2 = makePatch(files: ["b.swift", "c.swift", "d.swift"])
        let result = checker.check(patches: [p1, p2])

        XCTAssertEqual(result.totalUniqueFiles, 4)
        XCTAssertEqual(result.level, .normal)
    }

    func testMultiplePatches_combinedExceedsThreshold() {
        let files1 = Array(1...8).map { "f\($0).swift" }
        let files2 = Array(6...16).map { "f\($0).swift" }
        let result = checker.check(patches: [
            makePatch(files: files1),
            makePatch(files: files2),
        ])

        XCTAssertEqual(result.totalUniqueFiles, 16)
        XCTAssertEqual(result.level, .extraReview)
    }

    // MARK: - Direct files check

    func testCheckFiles_directly() {
        let files = Array(1...30).map { "file\($0).swift" }
        let result = checker.check(files: files)

        XCTAssertEqual(result.totalUniqueFiles, 30)
        XCTAssertEqual(result.level, .manualApproval)
    }

    func testCheckFiles_withDuplicates() {
        let files = ["a.swift", "b.swift", "a.swift", "c.swift"]
        let result = checker.check(files: files)
        XCTAssertEqual(result.totalUniqueFiles, 3)
    }

    // MARK: - canProceedWithoutGate

    func testCanProceedWithoutGate_normal() {
        let patch = makePatch(files: ["a.swift"])
        XCTAssertTrue(checker.canProceedWithoutGate(patches: [patch]))
    }

    func testCanProceedWithoutGate_extraReview() {
        let patch = makePatch(files: Array(1...15).map { "f\($0).swift" })
        XCTAssertFalse(checker.canProceedWithoutGate(patches: [patch]))
    }

    // MARK: - Empty

    func testEmptyPatchSet() {
        let result = checker.check(patches: [])
        XCTAssertEqual(result.totalUniqueFiles, 0)
        XCTAssertEqual(result.level, .normal)
    }

    // MARK: - classifyLevel

    func testClassifyLevel_boundaries() {
        XCTAssertEqual(checker.classifyLevel(fileCount: 0), .normal)
        XCTAssertEqual(checker.classifyLevel(fileCount: 12), .normal)
        XCTAssertEqual(checker.classifyLevel(fileCount: 13), .extraReview)
        XCTAssertEqual(checker.classifyLevel(fileCount: 25), .extraReview)
        XCTAssertEqual(checker.classifyLevel(fileCount: 26), .manualApproval)
    }
}
