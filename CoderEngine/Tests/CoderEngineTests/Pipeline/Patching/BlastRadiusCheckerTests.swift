import XCTest
@testable import CoderEngine

final class BlastRadiusCheckerTests: XCTestCase {

    let checker = BlastRadiusChecker()

    // MARK: - Helpers

    private func makePatch(
        files: [String],
        patchId: String = "p1"
    ) -> PatchManifest {
        PatchManifest(
            patchId: patchId, jobId: "j1", taskId: "t1",
            provider: "test", agentRole: .coder,
            touchedFiles: files, unifiedDiffPath: "/diff"
        )
    }

    // MARK: - Single Patch Tests

    func testNormalBlastRadius() {
        let patch = makePatch(files: Array(1...10).map { "file\($0).swift" })
        let result = checker.check(patch: patch)
        guard case .normal(let count) = result else {
            XCTFail("Expected .normal"); return
        }
        XCTAssertEqual(count, 10)
        XCTAssertFalse(result.isBlocked)
        XCTAssertFalse(result.needsExtraReview)
    }

    func testExtraReviewThreshold() {
        let patch = makePatch(files: Array(1...15).map { "file\($0).swift" })
        let result = checker.check(patch: patch)
        guard case .extraReviewRequired(let count) = result else {
            XCTFail("Expected .extraReviewRequired"); return
        }
        XCTAssertEqual(count, 15)
        XCTAssertFalse(result.isBlocked)
        XCTAssertTrue(result.needsExtraReview)
    }

    func testManualApprovalThreshold() {
        let patch = makePatch(files: Array(1...30).map { "file\($0).swift" })
        let result = checker.check(patch: patch)
        guard case .manualApprovalRequired(let count) = result else {
            XCTFail("Expected .manualApprovalRequired"); return
        }
        XCTAssertEqual(count, 30)
        XCTAssertTrue(result.isBlocked)
        XCTAssertTrue(result.needsExtraReview)
    }

    func testExactBoundary12IsNormal() {
        let patch = makePatch(files: Array(1...12).map { "f\($0)" })
        let result = checker.check(patch: patch)
        guard case .normal = result else {
            XCTFail("12 files should be .normal"); return
        }
    }

    func testExactBoundary13IsExtraReview() {
        let patch = makePatch(files: Array(1...13).map { "f\($0)" })
        let result = checker.check(patch: patch)
        guard case .extraReviewRequired = result else {
            XCTFail("13 files should be .extraReviewRequired"); return
        }
    }

    func testExactBoundary25IsExtraReview() {
        let patch = makePatch(files: Array(1...25).map { "f\($0)" })
        let result = checker.check(patch: patch)
        guard case .extraReviewRequired = result else {
            XCTFail("25 files should be .extraReviewRequired"); return
        }
    }

    func testExactBoundary26IsManualApproval() {
        let patch = makePatch(files: Array(1...26).map { "f\($0)" })
        let result = checker.check(patch: patch)
        guard case .manualApprovalRequired = result else {
            XCTFail("26 files should be .manualApprovalRequired"); return
        }
    }

    // MARK: - Patch Set Tests

    func testPatchSetDeduplicatesFiles() {
        let patch1 = makePatch(files: ["a.swift", "b.swift", "c.swift"], patchId: "p1")
        let patch2 = makePatch(files: ["b.swift", "c.swift", "d.swift"], patchId: "p2")
        let count = checker.uniqueFileCount(from: [patch1, patch2])
        XCTAssertEqual(count, 4, "Unique files: a, b, c, d")
    }

    func testPatchSetBlastRadiusCheck() {
        let files1 = Array(1...10).map { "file\($0).swift" }
        let files2 = Array(8...20).map { "file\($0).swift" }
        let patch1 = makePatch(files: files1, patchId: "p1")
        let patch2 = makePatch(files: files2, patchId: "p2")
        let result = checker.check(patchSet: [patch1, patch2])
        let uniqueCount = checker.uniqueFileCount(from: [patch1, patch2])
        XCTAssertEqual(uniqueCount, 20)
        guard case .extraReviewRequired = result else {
            XCTFail("20 unique files should be .extraReviewRequired"); return
        }
    }

    func testEmptyPatchSet() {
        let result = checker.check(patchSet: [])
        guard case .normal(let count) = result else {
            XCTFail("Empty patch set should be .normal"); return
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - Custom Thresholds

    func testCustomThresholds() {
        let custom = BlastRadiusChecker(
            thresholds: BlastRadiusThresholds(
                extraReviewThreshold: 5,
                manualApprovalThreshold: 10
            )
        )
        let result5 = custom.checkFileCount(5)
        guard case .normal = result5 else {
            XCTFail("5 files should be normal with threshold 5"); return
        }
        let result6 = custom.checkFileCount(6)
        guard case .extraReviewRequired = result6 else {
            XCTFail("6 files should need extra review with threshold 5"); return
        }
        let result11 = custom.checkFileCount(11)
        guard case .manualApprovalRequired = result11 else {
            XCTFail("11 files should need manual approval with threshold 10"); return
        }
    }

    // MARK: - UniqueFiles

    func testUniqueFilesExtraction() {
        let p1 = makePatch(files: ["x.swift", "y.swift"], patchId: "p1")
        let p2 = makePatch(files: ["y.swift", "z.swift"], patchId: "p2")
        let unique = checker.uniqueFiles(from: [p1, p2])
        XCTAssertEqual(unique, Set(["x.swift", "y.swift", "z.swift"]))
    }
}
