import Foundation

// MARK: - ApplyTransactionResult

/// Risultato dell'apply transaction (§5.6).
public enum ApplyTransactionResult: Sendable, Equatable {
    case success(appliedPatches: Int, totalFiles: Int)
    case awaitingApproval(reason: String)
    case patchConflict(details: String)
    case lockViolation(patchId: String, files: [String])
    case applyFailed(error: String)
    case rolledBack(reason: String)
    case riskGateBlocked(patchId: String, riskScore: Double)
}

// MARK: - PatchEngineProtocol

/// Protocollo per l'engine di patch reale (dry-run + apply).
public protocol PatchEngineProtocol: Sendable {
    func dryRun(patches: [PatchManifest]) async throws -> PatchEngineResult
    func apply(patches: [PatchManifest]) async throws -> PatchEngineResult
}

/// Risultato di un'operazione del patch engine.
public struct PatchEngineResult: Sendable, Equatable {
    public let success: Bool
    public let details: String
    public let appliedFiles: [String]

    public init(
        success: Bool,
        details: String = "",
        appliedFiles: [String] = []
    ) {
        self.success = success
        self.details = details
        self.appliedFiles = appliedFiles
    }
}

// MARK: - VerifyProtocol

/// Protocollo per la fase di verifica rapida post-apply (§8.9).
public protocol QuickVerifyProtocol: Sendable {
    func verify(
        files: [String],
        timeoutMs: Int
    ) async throws -> VerifyResult
}

/// Risultato della verifica post-apply.
public struct VerifyResult: Sendable, Equatable {
    public let success: Bool
    public let details: String

    public init(success: Bool, details: String = "") {
        self.success = success
        self.details = details
    }
}

// MARK: - PatchApplyTransaction

/// Esegue il flusso apply atomico completo (§5.6, §13.2):
///
/// 1. Validate manifest schema
/// 2. Validate risk score (§13.4)
/// 3. Blast radius check (§13.3)
/// 4. Verify lock ownership
/// 5. Create rollback point (§13.1)
/// 6. Dry-run patch
/// 7. Apply transaction
/// 8. Quick verify (§8.9)
/// 9. Commit or rollback
/// 10. Record rollback_record
///
/// Solo l'Orchestrator invoca questo componente.
public actor PatchApplyTransaction {

    private let lockManager: PipelineLockManager
    private let rollbackService: RollbackService
    private let patchEngine: PatchEngineProtocol
    private let verifier: QuickVerifyProtocol
    private let riskScorer: PatchRiskScorer
    private let blastChecker: BlastRadiusChecker

    /// Timeout per verify post-apply (ms)
    public static let verifyTimeoutMs = 30_000

    private(set) var totalTransactions: Int = 0
    private(set) var totalSuccesses: Int = 0
    private(set) var totalFailures: Int = 0
    private(set) var totalRollbacks: Int = 0

    public init(
        lockManager: PipelineLockManager,
        rollbackService: RollbackService,
        patchEngine: PatchEngineProtocol,
        verifier: QuickVerifyProtocol,
        riskScorer: PatchRiskScorer = PatchRiskScorer(),
        blastChecker: BlastRadiusChecker = BlastRadiusChecker()
    ) {
        self.lockManager = lockManager
        self.rollbackService = rollbackService
        self.patchEngine = patchEngine
        self.verifier = verifier
        self.riskScorer = riskScorer
        self.blastChecker = blastChecker
    }

    // MARK: - Execute Transaction

    /// Esegue l'intero flusso apply_transaction (§5.6).
    public func execute(
        job: PipelineJob,
        taskId: String,
        patches: [PatchManifest]
    ) async -> ApplyTransactionResult {
        totalTransactions += 1

        // Step 1: Validate manifest schema
        for patch in patches {
            do {
                try patch.validate()
            } catch {
                totalFailures += 1
                return .applyFailed(
                    error: "Manifest validation failed: \(error)"
                )
            }
        }

        // Step 2: Validate risk score (§13.4)
        for patch in patches {
            if riskScorer.requiresExtraReview(patch.riskScore) {
                totalFailures += 1
                return .riskGateBlocked(
                    patchId: patch.patchId,
                    riskScore: patch.riskScore
                )
            }
        }

        // Step 3: Blast radius check (§13.3)
        let blastResult = blastChecker.check(patches: patches)
        if blastResult.requiresManualApproval {
            totalFailures += 1
            return .awaitingApproval(
                reason: "Blast radius: \(blastResult.totalUniqueFiles) file "
                    + "(soglia \(BlastRadiusChecker.manualApprovalThreshold))"
            )
        }

        if blastResult.requiresExtraReview {
            totalFailures += 1
            return .awaitingApproval(
                reason: "Blast radius: \(blastResult.totalUniqueFiles) file "
                    + "(soglia \(BlastRadiusChecker.extraReviewThreshold))"
            )
        }

        // Step 4: Verify lock ownership
        let allTouchedFiles = Set(patches.flatMap(\.touchedFiles))
        let ownsLock = await lockManager.verifyOwnership(
            files: allTouchedFiles,
            taskId: taskId
        )
        if !ownsLock {
            totalFailures += 1
            return .lockViolation(
                patchId: patches.first?.patchId ?? "unknown",
                files: Array(allTouchedFiles)
            )
        }

        // Step 5: Create rollback point (§13.1)
        let rollbackPoint: RollbackPoint
        do {
            rollbackPoint = try await rollbackService.createRollbackPoint(
                patchId: patches.first?.patchId ?? "batch",
                strategy: job.rollbackStrategy,
                files: Array(allTouchedFiles)
            )
        } catch {
            totalFailures += 1
            return .applyFailed(
                error: "Rollback point creation failed: \(error)"
            )
        }

        // Step 6: Dry-run patch
        let dryRunResult: PatchEngineResult
        do {
            dryRunResult = try await patchEngine.dryRun(patches: patches)
        } catch {
            try? await rollbackService.cleanup(rollbackPoint: rollbackPoint)
            totalFailures += 1
            return .patchConflict(details: "Dry-run error: \(error)")
        }

        if !dryRunResult.success {
            try? await rollbackService.cleanup(rollbackPoint: rollbackPoint)
            totalFailures += 1
            return .patchConflict(details: dryRunResult.details)
        }

        // Step 7: Apply
        let applyResult: PatchEngineResult
        do {
            applyResult = try await patchEngine.apply(patches: patches)
        } catch {
            _ = try? await rollbackService.execute(
                rollbackPoint: rollbackPoint,
                jobId: job.jobId,
                taskId: taskId
            )
            totalRollbacks += 1
            totalFailures += 1
            return .applyFailed(error: "Apply error: \(error)")
        }

        if !applyResult.success {
            _ = try? await rollbackService.execute(
                rollbackPoint: rollbackPoint,
                jobId: job.jobId,
                taskId: taskId
            )
            totalRollbacks += 1
            totalFailures += 1
            return .applyFailed(error: applyResult.details)
        }

        // Step 8: Quick verify (§8.9)
        let verifyResult: VerifyResult
        do {
            verifyResult = try await verifier.verify(
                files: Array(allTouchedFiles),
                timeoutMs: Self.verifyTimeoutMs
            )
        } catch {
            _ = try? await rollbackService.execute(
                rollbackPoint: rollbackPoint,
                jobId: job.jobId,
                taskId: taskId
            )
            totalRollbacks += 1
            totalFailures += 1
            return .rolledBack(reason: "Verify error: \(error)")
        }

        if !verifyResult.success {
            _ = try? await rollbackService.execute(
                rollbackPoint: rollbackPoint,
                jobId: job.jobId,
                taskId: taskId
            )
            totalRollbacks += 1
            totalFailures += 1
            return .rolledBack(reason: verifyResult.details)
        }

        // Step 9: Cleanup rollback point
        try? await rollbackService.cleanup(rollbackPoint: rollbackPoint)

        totalSuccesses += 1
        return .success(
            appliedPatches: patches.count,
            totalFiles: allTouchedFiles.count
        )
    }

    // MARK: - Stats

    public var stats: (
        total: Int, successes: Int, failures: Int, rollbacks: Int
    ) {
        (totalTransactions, totalSuccesses, totalFailures, totalRollbacks)
    }
}
