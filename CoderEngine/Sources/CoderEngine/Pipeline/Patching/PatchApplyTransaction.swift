import Foundation

// MARK: - ApplyTransactionResult

/// Risultato di un'apply transaction (§5.6).
public enum ApplyTransactionResult: Sendable, Equatable {
    case success(appliedFiles: Int)
    case patchConflict(reason: String)
    case lockViolation(file: String)
    case blastRadiusBlocked(fileCount: Int)
    case extraReviewRequired(reason: String)
    case applyFailed(reason: String)
    case verifyFailed(rollbackRecord: RollbackRecord)
    case rolledBack(rollbackRecord: RollbackRecord)
    case awaitingApproval(fileCount: Int)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - PatchEngineDelegate

/// Delegate per operazioni di apply/dry-run delle patch.
public protocol PatchEngineDelegate: Sendable {
    func dryRun(patches: [PatchManifest]) async throws -> Bool
    func apply(patches: [PatchManifest]) async throws -> Bool
    func quickVerify(
        touchedFiles: [String], timeoutMs: Int
    ) async throws -> Bool
}

// MARK: - ApplyTransactionError

public enum ApplyTransactionError: Error, Sendable, Equatable {
    case emptyPatchSet
    case validationFailed(reason: String)
    case lockVerificationFailed(taskId: String, file: String)
    case dryRunFailed(reason: String)
    case applyFailed(reason: String)
    case verifyFailed(reason: String)
    case rollbackTriggered(reason: String)
}

// MARK: - PatchApplyTransaction

/// Orchestratore della transazione di apply atomico (§5.6).
///
/// Flusso completo (§13.2):
/// 1. Validate manifest schema
/// 2. Validate risk score → extra review se > 0.7
/// 3. Blast radius check → extra review/manual approval
/// 4. Lock verification
/// 5. Create rollback point (§13.1)
/// 6. Dry-run
/// 7. Apply
/// 8. Quick verify
/// 9. Cleanup o rollback
public actor PatchApplyTransaction {

    private let lockManager: PipelineLockManager
    private let rollbackService: RollbackService
    private let riskScorer: PatchRiskScorer
    private let blastRadiusChecker: BlastRadiusChecker
    private let patchEngine: PatchEngineDelegate
    private let verifyTimeoutMs: Int

    public init(
        lockManager: PipelineLockManager,
        rollbackService: RollbackService,
        riskScorer: PatchRiskScorer = PatchRiskScorer(),
        blastRadiusChecker: BlastRadiusChecker = BlastRadiusChecker(),
        patchEngine: PatchEngineDelegate,
        verifyTimeoutMs: Int = 30_000
    ) {
        self.lockManager = lockManager
        self.rollbackService = rollbackService
        self.riskScorer = riskScorer
        self.blastRadiusChecker = blastRadiusChecker
        self.patchEngine = patchEngine
        self.verifyTimeoutMs = verifyTimeoutMs
    }

    // MARK: - Execute Transaction

    /// Esegue la transazione di apply atomico (§5.6).
    public func execute(
        patchSet: [PatchManifest],
        taskId: String,
        job: PipelineJob
    ) async -> ApplyTransactionResult {
        guard !patchSet.isEmpty else {
            return .applyFailed(reason: "Empty patch set")
        }

        // Step 1: Validate manifests
        for patch in patchSet {
            do {
                try patch.validate()
            } catch {
                return .applyFailed(
                    reason: "Manifest validation failed: \(error.localizedDescription)"
                )
            }
        }

        // Step 2: Risk check — extra review se qualche patch > 0.7
        for patch in patchSet {
            if patch.requiresExtraReview {
                return .extraReviewRequired(
                    reason: "Patch \(patch.patchId) risk_score \(patch.riskScore) > 0.7"
                )
            }
        }

        // Step 3: Blast radius check
        let radiusResult = blastRadiusChecker.check(patchSet: patchSet)
        switch radiusResult {
        case .manualApprovalRequired(let count):
            return .awaitingApproval(fileCount: count)
        case .extraReviewRequired:
            return .extraReviewRequired(
                reason: "Blast radius: \(radiusResult.fileCount) files > 12 threshold"
            )
        case .normal:
            break
        }

        // Step 4: Lock verification
        let allFiles = blastRadiusChecker.uniqueFiles(from: patchSet)
        let lockVerified = await lockManager.verifyOwnership(
            files: allFiles, taskId: taskId
        )
        if !lockVerified {
            return .lockViolation(
                file: allFiles.first ?? "unknown"
            )
        }

        // Step 5: Rollback point
        let rollbackRef: RollbackReference
        do {
            rollbackRef = try await rollbackService.createRollbackPoint(
                strategy: job.rollbackStrategy,
                patchId: patchSet.first?.patchId ?? taskId,
                files: Array(allFiles)
            )
        } catch {
            return .applyFailed(
                reason: "Failed to create rollback point: \(error)"
            )
        }

        // Step 6: Dry run
        let dryRunSuccess: Bool
        do {
            dryRunSuccess = try await patchEngine.dryRun(patches: patchSet)
        } catch {
            try? await rollbackService.cleanup(rollbackRef: rollbackRef)
            return .patchConflict(reason: "Dry-run exception: \(error)")
        }
        if !dryRunSuccess {
            try? await rollbackService.cleanup(rollbackRef: rollbackRef)
            return .patchConflict(reason: "Dry-run detected conflicts")
        }

        // Step 7: Apply
        let applySuccess: Bool
        do {
            applySuccess = try await patchEngine.apply(patches: patchSet)
        } catch {
            return await rollbackAndReturn(
                ref: rollbackRef, jobId: job.jobId,
                taskId: taskId, reason: "Apply exception: \(error)"
            )
        }
        if !applySuccess {
            return await rollbackAndReturn(
                ref: rollbackRef, jobId: job.jobId,
                taskId: taskId, reason: "Apply returned false"
            )
        }

        // Step 8: Quick verify
        let verifySuccess: Bool
        do {
            verifySuccess = try await patchEngine.quickVerify(
                touchedFiles: Array(allFiles),
                timeoutMs: verifyTimeoutMs
            )
        } catch {
            return await rollbackAndReturn(
                ref: rollbackRef, jobId: job.jobId,
                taskId: taskId,
                reason: "Verify exception: \(error)"
            )
        }
        if !verifySuccess {
            let record = await rollbackAndGetRecord(
                ref: rollbackRef, jobId: job.jobId, taskId: taskId
            )
            if let record {
                return .verifyFailed(rollbackRecord: record)
            }
            return .applyFailed(
                reason: "Verify failed and rollback could not produce record"
            )
        }

        // Step 9: Cleanup rollback point
        try? await rollbackService.cleanup(rollbackRef: rollbackRef)

        return .success(appliedFiles: allFiles.count)
    }

    // MARK: - Private Helpers

    private func rollbackAndReturn(
        ref: RollbackReference,
        jobId: String,
        taskId: String,
        reason: String
    ) async -> ApplyTransactionResult {
        let record = await rollbackAndGetRecord(
            ref: ref, jobId: jobId, taskId: taskId
        )
        if let record {
            return .rolledBack(rollbackRecord: record)
        }
        return .applyFailed(
            reason: "\(reason) (rollback also failed)"
        )
    }

    private func rollbackAndGetRecord(
        ref: RollbackReference,
        jobId: String,
        taskId: String
    ) async -> RollbackRecord? {
        do {
            return try await rollbackService.execute(
                rollbackRef: ref, jobId: jobId, taskId: taskId
            )
        } catch {
            return nil
        }
    }
}
