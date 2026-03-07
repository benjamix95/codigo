import XCTest
@testable import CoderEngine

// MARK: - Mock PatchEngine

private final class MockPatchEngine: PatchEngineProtocol, @unchecked Sendable {
    var dryRunResult = PatchEngineResult(success: true)
    var applyResult = PatchEngineResult(success: true)
    var dryRunCallCount = 0
    var applyCallCount = 0
    var shouldThrowOnDryRun = false
    var shouldThrowOnApply = false

    func dryRun(patches: [PatchManifest]) async throws -> PatchEngineResult {
        dryRunCallCount += 1
        if shouldThrowOnDryRun {
            throw NSError(
                domain: "test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "dry-run crash"]
            )
        }
        return dryRunResult
    }

    func apply(patches: [PatchManifest]) async throws -> PatchEngineResult {
        applyCallCount += 1
        if shouldThrowOnApply {
            throw NSError(
                domain: "test", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "apply crash"]
            )
        }
        return applyResult
    }
}

// MARK: - Mock QuickVerifier

private final class MockVerifier: QuickVerifyProtocol, @unchecked Sendable {
    var result = VerifyResult(success: true)
    var callCount = 0
    var shouldThrow = false

    func verify(
        files: [String], timeoutMs: Int
    ) async throws -> VerifyResult {
        callCount += 1
        if shouldThrow {
            throw NSError(
                domain: "test", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "verify crash"]
            )
        }
        return result
    }
}

// MARK: - Mock RollbackDelegate (minimal)

private final class MinimalRollbackDelegate: RollbackServiceDelegate,
    @unchecked Sendable
{
    var checksums: [String: String] = [:]

    func createBranch(name: String) async throws {}
    func switchToBranch(name: String) async throws {}
    func deleteBranch(name: String) async throws {}
    func restoreFileFromBranch(branch: String, file: String) async throws {}
    func stashPush(
        message: String, files: [String]
    ) async throws -> String { "stash@{0}" }
    func stashPop(stashId: String) async throws {}
    func stashDrop(stashId: String) async throws {}
    func copyFilesToSnapshot(files: [String], dir: String) async throws {}
    func restoreFileFromSnapshot(
        snapshotDir: String, file: String
    ) async throws {}
    func deleteDirectory(dir: String) async throws {}
    func computeChecksum(file: String) async throws -> String {
        checksums[file] ?? "checksum_\(file)"
    }
    func fileExists(path: String) async -> Bool { true }
}

// MARK: - Tests

final class PatchApplyTransactionTests: XCTestCase {

    private func makeJob() -> PipelineJob {
        PipelineJob(
            jobId: "j1",
            workspace: "/test",
            request: "test request",
            rollbackStrategy: .gitBranch
        )
    }

    private func makePatch(
        patchId: String = "p1",
        files: [String] = ["a.swift"],
        riskScore: Double = 0.3
    ) -> PatchManifest {
        PatchManifest(
            patchId: patchId,
            jobId: "j1",
            taskId: "t1",
            provider: "gpt",
            agentRole: .coder,
            touchedFiles: files,
            unifiedDiffPath: "diff.patch",
            riskScore: riskScore
        )
    }

    private func makeSystem() async -> (
        PatchApplyTransaction, PipelineLockManager, MockPatchEngine,
        MockVerifier
    ) {
        let lockManager = PipelineLockManager()
        let rbDelegate = MinimalRollbackDelegate()
        let rollbackService = RollbackService(delegate: rbDelegate)
        let patchEngine = MockPatchEngine()
        let verifier = MockVerifier()

        let transaction = PatchApplyTransaction(
            lockManager: lockManager,
            rollbackService: rollbackService,
            patchEngine: patchEngine,
            verifier: verifier
        )

        return (transaction, lockManager, patchEngine, verifier)
    }

    // MARK: - Success path

    func testFullSuccess() async {
        let (tx, lockManager, engine, verifier) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .success(let count, let files) = result {
            XCTAssertEqual(count, 1)
            XCTAssertEqual(files, 1)
        } else {
            XCTFail("Expected success, got \(result)")
        }

        XCTAssertEqual(engine.dryRunCallCount, 1)
        XCTAssertEqual(engine.applyCallCount, 1)
        XCTAssertEqual(verifier.callCount, 1)

        let stats = await tx.stats
        XCTAssertEqual(stats.total, 1)
        XCTAssertEqual(stats.successes, 1)
    }

    // MARK: - Validation failure

    func testManifestValidationFailure() async {
        let (tx, lockManager, _, _) = await makeSystem()
        let job = makeJob()
        let badPatch = PatchManifest(
            patchId: "",
            jobId: "j1",
            taskId: "t1",
            provider: "gpt",
            agentRole: .coder,
            touchedFiles: ["a.swift"],
            unifiedDiffPath: "diff.patch"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [badPatch]
        )

        if case .applyFailed(let error) = result {
            XCTAssertTrue(error.contains("validation"))
        } else {
            XCTFail("Expected applyFailed, got \(result)")
        }
    }

    // MARK: - Risk gate

    func testRiskGateBlocked() async {
        let (tx, lockManager, _, _) = await makeSystem()
        let job = makeJob()
        let riskyPatch = makePatch(riskScore: 0.85)

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [riskyPatch]
        )

        if case .riskGateBlocked(let pid, let score) = result {
            XCTAssertEqual(pid, "p1")
            XCTAssertEqual(score, 0.85)
        } else {
            XCTFail("Expected riskGateBlocked, got \(result)")
        }
    }

    // MARK: - Blast radius

    func testBlastRadiusManualApproval() async {
        let (tx, _, _, _) = await makeSystem()
        let job = makeJob()
        let bigPatch = makePatch(
            files: Array(1...26).map { "f\($0).swift" },
            riskScore: 0.3
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [bigPatch]
        )

        if case .awaitingApproval = result {
            // ok
        } else {
            XCTFail("Expected awaitingApproval, got \(result)")
        }
    }

    func testBlastRadiusExtraReviewRequiresApproval() async {
        let (tx, _, _, _) = await makeSystem()
        let job = makeJob()
        let mediumPatch = makePatch(
            files: Array(1...13).map { "f\($0).swift" },
            riskScore: 0.3
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [mediumPatch]
        )

        if case .awaitingApproval = result {
            // ok
        } else {
            XCTFail("Expected awaitingApproval, got \(result)")
        }
    }

    // MARK: - Lock violation

    func testLockViolation() async {
        let (tx, _, _, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .lockViolation(let pid, _) = result {
            XCTAssertEqual(pid, "p1")
        } else {
            XCTFail("Expected lockViolation, got \(result)")
        }
    }

    // MARK: - Dry-run failure

    func testDryRunFailure() async {
        let (tx, lockManager, engine, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        engine.dryRunResult = PatchEngineResult(
            success: false, details: "conflict in a.swift"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .patchConflict(let details) = result {
            XCTAssertTrue(details.contains("conflict"))
        } else {
            XCTFail("Expected patchConflict, got \(result)")
        }
    }

    func testDryRunThrows() async {
        let (tx, lockManager, engine, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        engine.shouldThrowOnDryRun = true

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .patchConflict = result {
            // ok
        } else {
            XCTFail("Expected patchConflict, got \(result)")
        }
    }

    // MARK: - Apply failure

    func testApplyFailure() async {
        let (tx, lockManager, engine, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        engine.applyResult = PatchEngineResult(
            success: false, details: "apply error"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .applyFailed = result {
            // ok
        } else {
            XCTFail("Expected applyFailed, got \(result)")
        }

        let stats = await tx.stats
        XCTAssertEqual(stats.rollbacks, 1)
    }

    func testApplyThrows_triggersRollback() async {
        let (tx, lockManager, engine, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        engine.shouldThrowOnApply = true

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .applyFailed = result {
            // ok
        } else {
            XCTFail("Expected applyFailed, got \(result)")
        }

        let stats = await tx.stats
        XCTAssertEqual(stats.rollbacks, 1)
    }

    // MARK: - Verify failure triggers rollback

    func testVerifyFailure_triggersRollback() async {
        let (tx, lockManager, _, verifier) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        verifier.result = VerifyResult(
            success: false, details: "lint error"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .rolledBack(let reason) = result {
            XCTAssertTrue(reason.contains("lint"))
        } else {
            XCTFail("Expected rolledBack, got \(result)")
        }

        let stats = await tx.stats
        XCTAssertEqual(stats.rollbacks, 1)
    }

    func testVerifyThrows_triggersRollback() async {
        let (tx, lockManager, _, verifier) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        verifier.shouldThrow = true

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [patch]
        )

        if case .rolledBack = result {
            // ok
        } else {
            XCTFail("Expected rolledBack, got \(result)")
        }
    }

    // MARK: - Multiple patches

    func testMultiplePatches_success() async {
        let (tx, lockManager, _, _) = await makeSystem()
        let job = makeJob()
        let p1 = makePatch(patchId: "p1", files: ["a.swift"])
        let p2 = makePatch(patchId: "p2", files: ["b.swift"])

        await lockManager.acquire(
            scope: LockScope(files: ["a.swift", "b.swift"]),
            taskId: "t1"
        )

        let result = await tx.execute(
            job: job, taskId: "t1", patches: [p1, p2]
        )

        if case .success(let count, let files) = result {
            XCTAssertEqual(count, 2)
            XCTAssertEqual(files, 2)
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }

    // MARK: - Stats accumulation

    func testStatsAccumulate() async {
        let (tx, lockManager, engine, _) = await makeSystem()
        let job = makeJob()
        let patch = makePatch()

        await lockManager.acquire(
            scope: LockScope(files: Set(patch.touchedFiles)),
            taskId: "t1"
        )

        _ = await tx.execute(job: job, taskId: "t1", patches: [patch])
        _ = await tx.execute(job: job, taskId: "t1", patches: [patch])

        engine.applyResult = PatchEngineResult(
            success: false, details: "fail"
        )
        _ = await tx.execute(job: job, taskId: "t1", patches: [patch])

        let stats = await tx.stats
        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.successes, 2)
        XCTAssertEqual(stats.failures, 1)
    }
}
