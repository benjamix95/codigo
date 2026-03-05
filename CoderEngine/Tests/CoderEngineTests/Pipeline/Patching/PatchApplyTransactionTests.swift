import XCTest
@testable import CoderEngine

// MARK: - MockPatchEngine

final class MockPatchEngine: PatchEngineDelegate, @unchecked Sendable {
    var dryRunResult = true
    var applyResult = true
    var verifyResult = true
    var dryRunShouldThrow = false
    var applyShouldThrow = false
    var verifyShouldThrow = false
    var dryRunCallCount = 0
    var applyCallCount = 0
    var verifyCallCount = 0

    func dryRun(patches: [PatchManifest]) async throws -> Bool {
        dryRunCallCount += 1
        if dryRunShouldThrow { throw ApplyTransactionError.dryRunFailed(reason: "mock") }
        return dryRunResult
    }

    func apply(patches: [PatchManifest]) async throws -> Bool {
        applyCallCount += 1
        if applyShouldThrow { throw ApplyTransactionError.applyFailed(reason: "mock") }
        return applyResult
    }

    func quickVerify(touchedFiles: [String], timeoutMs: Int) async throws -> Bool {
        verifyCallCount += 1
        if verifyShouldThrow { throw ApplyTransactionError.verifyFailed(reason: "mock") }
        return verifyResult
    }
}

// MARK: - PatchApplyTransactionTests

final class PatchApplyTransactionTests: XCTestCase {

    var rollbackDelegate: MockRollbackDelegate!
    var patchEngine: MockPatchEngine!
    var lockManager: PipelineLockManager!
    var rollbackService: RollbackService!

    override func setUp() async throws {
        rollbackDelegate = MockRollbackDelegate()
        rollbackDelegate.existingFiles = ["a.swift", "b.swift", "c.swift"]
        rollbackDelegate.checksums = [
            "a.swift": "h1", "b.swift": "h2", "c.swift": "h3"
        ]
        patchEngine = MockPatchEngine()
        lockManager = PipelineLockManager()
        rollbackService = RollbackService(
            delegate: rollbackDelegate, workspacePath: "/ws"
        )
    }

    private func makeJob() -> PipelineJob {
        PipelineJob(
            jobId: "j1", workspace: "/ws", request: "test",
            rollbackStrategy: .gitBranch
        )
    }

    private func makePatch(
        files: [String] = ["a.swift", "b.swift"],
        riskScore: Double = 0.3,
        patchId: String = "p1"
    ) -> PatchManifest {
        PatchManifest(
            patchId: patchId, jobId: "j1", taskId: "t1",
            provider: "test", agentRole: .coder,
            touchedFiles: files, unifiedDiffPath: "/diff",
            riskScore: riskScore
        )
    }

    private func makeTransaction() -> PatchApplyTransaction {
        PatchApplyTransaction(
            lockManager: lockManager,
            rollbackService: rollbackService,
            patchEngine: patchEngine
        )
    }

    private func acquireLocks(files: [String], taskId: String = "t1") async {
        let scope = LockScope(files: Set(files))
        await lockManager.acquire(scope: scope, taskId: taskId)
    }

    // MARK: - Success Path

    func testSuccessfulApply() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .success(let count) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(patchEngine.dryRunCallCount, 1)
        XCTAssertEqual(patchEngine.applyCallCount, 1)
        XCTAssertEqual(patchEngine.verifyCallCount, 1)
    }

    // MARK: - Empty Patch Set

    func testEmptyPatchSetFails() async {
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [], taskId: "t1", job: makeJob()
        )
        guard case .applyFailed(let reason) = result else {
            XCTFail("Expected applyFailed"); return
        }
        XCTAssertTrue(reason.contains("Empty"))
    }

    // MARK: - Risk Score Extra Review

    func testHighRiskScoreRequiresExtraReview() async {
        await acquireLocks(files: ["a.swift"])
        let tx = makeTransaction()
        let patch = makePatch(files: ["a.swift"], riskScore: 0.8)
        let result = await tx.execute(
            patchSet: [patch], taskId: "t1", job: makeJob()
        )
        guard case .extraReviewRequired = result else {
            XCTFail("Expected extraReviewRequired, got \(result)"); return
        }
    }

    // MARK: - Blast Radius

    func testBlastRadiusManualApproval() async {
        let files = Array(1...30).map { "file\($0).swift" }
        await acquireLocks(files: files)
        let tx = makeTransaction()
        let patch = makePatch(files: files)
        let result = await tx.execute(
            patchSet: [patch], taskId: "t1", job: makeJob()
        )
        guard case .awaitingApproval(let count) = result else {
            XCTFail("Expected awaitingApproval, got \(result)"); return
        }
        XCTAssertEqual(count, 30)
    }

    func testBlastRadiusExtraReview() async {
        let files = Array(1...15).map { "file\($0).swift" }
        await acquireLocks(files: files)
        let tx = makeTransaction()
        let patch = makePatch(files: files)
        let result = await tx.execute(
            patchSet: [patch], taskId: "t1", job: makeJob()
        )
        guard case .extraReviewRequired = result else {
            XCTFail("Expected extraReviewRequired, got \(result)"); return
        }
    }

    // MARK: - Lock Violation

    func testLockViolation() async {
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .lockViolation = result else {
            XCTFail("Expected lockViolation, got \(result)"); return
        }
    }

    // MARK: - Dry Run Failure

    func testDryRunFailureReturnsPatchConflict() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.dryRunResult = false
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .patchConflict = result else {
            XCTFail("Expected patchConflict, got \(result)"); return
        }
    }

    func testDryRunExceptionReturnsPatchConflict() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.dryRunShouldThrow = true
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .patchConflict = result else {
            XCTFail("Expected patchConflict, got \(result)"); return
        }
    }

    // MARK: - Apply Failure → Rollback

    func testApplyFailureTriggersRollback() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.applyResult = false
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .rolledBack = result else {
            XCTFail("Expected rolledBack, got \(result)"); return
        }
    }

    func testApplyExceptionTriggersRollback() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.applyShouldThrow = true
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .rolledBack = result else {
            XCTFail("Expected rolledBack, got \(result)"); return
        }
    }

    // MARK: - Verify Failure → Rollback

    func testVerifyFailureTriggersRollback() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.verifyResult = false
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        guard case .verifyFailed(let record) = result else {
            XCTFail("Expected verifyFailed, got \(result)"); return
        }
        XCTAssertEqual(record.strategy, .gitBranch)
        XCTAssertTrue(record.verificationPassed)
    }

    func testVerifyExceptionTriggersRollback() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.verifyShouldThrow = true
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: makeJob()
        )
        switch result {
        case .rolledBack, .verifyFailed, .applyFailed:
            break
        default:
            XCTFail("Expected rollback-related result, got \(result)")
        }
    }

    // MARK: - Manifest Validation Failure

    func testInvalidManifestFails() async {
        let badPatch = PatchManifest(
            patchId: "", jobId: "j1", taskId: "t1",
            provider: "test", agentRole: .coder,
            touchedFiles: ["a.swift"], unifiedDiffPath: "/diff"
        )
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [badPatch], taskId: "t1", job: makeJob()
        )
        guard case .applyFailed(let reason) = result else {
            XCTFail("Expected applyFailed, got \(result)"); return
        }
        XCTAssertTrue(reason.contains("validation"))
    }

    // MARK: - Multiple Patches

    func testMultiplePatchesDeduplicateFiles() async {
        let files1 = ["a.swift", "b.swift"]
        let files2 = ["b.swift", "c.swift"]
        await acquireLocks(files: ["a.swift", "b.swift", "c.swift"])
        let tx = makeTransaction()
        let p1 = makePatch(files: files1, patchId: "p1")
        let p2 = makePatch(files: files2, patchId: "p2")
        let result = await tx.execute(
            patchSet: [p1, p2], taskId: "t1", job: makeJob()
        )
        guard case .success(let count) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertEqual(count, 3, "Unique files: a, b, c")
    }

    // MARK: - Different Rollback Strategies

    func testGitStashStrategy() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.applyResult = false
        var job = makeJob()
        job.rollbackStrategy = .gitStash
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: job
        )
        guard case .rolledBack(let record) = result else {
            XCTFail("Expected rolledBack, got \(result)"); return
        }
        XCTAssertEqual(record.strategy, .gitStash)
    }

    func testFilesystemSnapshotStrategy() async {
        await acquireLocks(files: ["a.swift", "b.swift"])
        patchEngine.applyResult = false
        var job = makeJob()
        job.rollbackStrategy = .filesystemSnapshot
        let tx = makeTransaction()
        let result = await tx.execute(
            patchSet: [makePatch()], taskId: "t1", job: job
        )
        guard case .rolledBack(let record) = result else {
            XCTFail("Expected rolledBack, got \(result)"); return
        }
        XCTAssertEqual(record.strategy, .filesystemSnapshot)
    }
}
