import Foundation
import CryptoKit

// MARK: - RollbackPoint

/// Punto di rollback creato prima dell'apply (§13.1 invariante 3).
public struct RollbackPoint: Sendable, Equatable {
    public let rollbackId: String
    public let patchId: String
    public let strategy: RollbackStrategy
    public let files: [String]
    public let checksums: [String: String]
    public let branchName: String?
    public let stashId: String?
    public let snapshotDir: String?
    public let createdAt: Date

    public init(
        rollbackId: String,
        patchId: String,
        strategy: RollbackStrategy,
        files: [String],
        checksums: [String: String],
        branchName: String? = nil,
        stashId: String? = nil,
        snapshotDir: String? = nil,
        createdAt: Date = Date()
    ) {
        self.rollbackId = rollbackId
        self.patchId = patchId
        self.strategy = strategy
        self.files = files
        self.checksums = checksums
        self.branchName = branchName
        self.stashId = stashId
        self.snapshotDir = snapshotDir
        self.createdAt = createdAt
    }
}

// MARK: - RollbackError

public enum RollbackError: Error, Sendable, Equatable {
    case strategyMismatch(expected: RollbackStrategy, got: RollbackStrategy)
    case checksumMismatch(file: String, expected: String, actual: String)
    case branchNotFound(String)
    case stashNotFound(String)
    case snapshotDirNotFound(String)
    case fileNotFound(String)
    case executionFailed(String)
    case timeout(elapsedMs: Int)
    case cleanupFailed(String)
}

// MARK: - RollbackServiceDelegate

/// Protocollo per operazioni I/O reali (git, filesystem).
/// Permette di mockare negli unit test.
public protocol RollbackServiceDelegate: Sendable {
    func createBranch(name: String) async throws
    func switchToBranch(name: String) async throws
    func deleteBranch(name: String) async throws
    func restoreFileFromBranch(branch: String, file: String) async throws
    func stashPush(message: String, files: [String]) async throws -> String
    func stashPop(stashId: String) async throws
    func stashDrop(stashId: String) async throws
    func copyFilesToSnapshot(files: [String], dir: String) async throws
    func restoreFileFromSnapshot(snapshotDir: String, file: String) async throws
    func deleteDirectory(dir: String) async throws
    func computeChecksum(file: String) async throws -> String
    func fileExists(path: String) async -> Bool
}

// MARK: - RollbackService

/// Servizio di rollback con 3 strategie concrete (§13.1).
///
/// Invarianti MUST:
/// 1. Rollback ripristina stato identico al pre-apply (verifica checksum)
/// 2. Completamento entro 10.000ms
/// 3. Failure → abort immediato job (stato `aborted`)
/// 4. Ogni rollback produce un `RollbackRecord`
public actor RollbackService {

    private let delegate: RollbackServiceDelegate
    private var activePoints: [String: RollbackPoint] = [:]
    private(set) var totalRollbacksCreated: Int = 0
    private(set) var totalRollbacksExecuted: Int = 0
    private(set) var totalRollbacksFailed: Int = 0
    private(set) var totalCleanups: Int = 0

    public static let timeoutMs = 10_000

    public init(delegate: RollbackServiceDelegate) {
        self.delegate = delegate
    }

    // MARK: - Create Rollback Point

    /// Crea un rollback point PRIMA dell'apply (§13.1 inv.3).
    public func createRollbackPoint(
        patchId: String,
        strategy: RollbackStrategy,
        files: [String]
    ) async throws -> RollbackPoint {
        let validatedFiles = try files.map { try validatedRelativeFilePath($0) }

        let validatedPatchId: String
        if strategy == .filesystemSnapshot {
            validatedPatchId = try validatedPatchIdComponent(patchId)
        } else {
            validatedPatchId = patchId
        }

        let rollbackId = "rb_\(validatedPatchId)_\(UUID().uuidString.prefix(8))"

        var checksums: [String: String] = [:]
        for file in validatedFiles {
            if await delegate.fileExists(path: file) {
                checksums[file] = try await delegate.computeChecksum(file: file)
            }
        }

        var branchName: String?
        var stashId: String?
        var snapshotDir: String?

        switch strategy {
        case .gitBranch:
            let name = "rollback_\(validatedPatchId)"
            try await delegate.createBranch(name: name)
            branchName = name

        case .gitStash:
            let sid = try await delegate.stashPush(
                message: "rollback_\(patchId)",
                files: validatedFiles
            )
            stashId = sid

        case .filesystemSnapshot:
            let dir = "artifacts/rollback/\(validatedPatchId)"
            try await delegate.copyFilesToSnapshot(files: validatedFiles, dir: dir)
            snapshotDir = dir
        }

        let point = RollbackPoint(
            rollbackId: rollbackId,
            patchId: validatedPatchId,
            strategy: strategy,
            files: validatedFiles,
            checksums: checksums,
            branchName: branchName,
            stashId: stashId,
            snapshotDir: snapshotDir
        )

        activePoints[rollbackId] = point
        totalRollbacksCreated += 1
        return point
    }

    // MARK: - Execute Rollback

    /// Esegue il rollback ripristinando lo stato pre-apply (§5.7).
    ///
    /// - Returns: `RollbackRecord` con status success/failed
    /// - Throws: `RollbackError` se il rollback fallisce
    public func execute(
        rollbackPoint: RollbackPoint,
        jobId: String,
        taskId: String
    ) async throws -> RollbackRecord {
        let startTime = Date()

        do {
            switch rollbackPoint.strategy {
            case .gitBranch:
                guard let branch = rollbackPoint.branchName else {
                    throw RollbackError.branchNotFound("nil")
                }
                for file in rollbackPoint.files {
                    try await delegate.restoreFileFromBranch(
                        branch: branch, file: file
                    )
                }
                try await delegate.deleteBranch(name: branch)

            case .gitStash:
                guard let sid = rollbackPoint.stashId else {
                    throw RollbackError.stashNotFound("nil")
                }
                try await delegate.stashPop(stashId: sid)

            case .filesystemSnapshot:
                guard let dir = rollbackPoint.snapshotDir else {
                    throw RollbackError.snapshotDirNotFound("nil")
                }

                let validatedDir = try validatedSnapshotDirectory(dir)
                let validatedFiles = try rollbackPoint.files.map {
                    try validatedRelativeFilePath($0)
                }

                for file in validatedFiles {
                    try await delegate.restoreFileFromSnapshot(
                        snapshotDir: validatedDir, file: file
                    )
                }
                try await delegate.deleteDirectory(dir: validatedDir)
            }

            let verificationPassed = try await verifyChecksums(
                rollbackPoint: rollbackPoint
            )

            let completedAt = Date()
            let elapsedMs = Int(
                completedAt.timeIntervalSince(startTime) * 1000
            )

            if elapsedMs > Self.timeoutMs {
                totalRollbacksFailed += 1
                throw RollbackError.timeout(elapsedMs: elapsedMs)
            }

            totalRollbacksExecuted += 1
            activePoints.removeValue(forKey: rollbackPoint.rollbackId)

            return RollbackRecord(
                rollbackId: rollbackPoint.rollbackId,
                jobId: jobId,
                taskId: taskId,
                patchId: rollbackPoint.patchId,
                strategy: rollbackPoint.strategy,
                rollbackRef: rollbackPoint.rollbackId,
                filesRestored: rollbackPoint.files,
                startedAt: startTime,
                completedAt: completedAt,
                status: .success,
                verificationPassed: verificationPassed,
                checksums: rollbackPoint.checksums
            )

        } catch let error as RollbackError {
            totalRollbacksFailed += 1
            let record = RollbackRecord(
                rollbackId: rollbackPoint.rollbackId,
                jobId: jobId,
                taskId: taskId,
                patchId: rollbackPoint.patchId,
                strategy: rollbackPoint.strategy,
                rollbackRef: rollbackPoint.rollbackId,
                filesRestored: rollbackPoint.files,
                startedAt: startTime,
                completedAt: Date(),
                status: .failed,
                verificationPassed: false,
                checksums: rollbackPoint.checksums
            )
            _ = record
            throw error

        } catch {
            totalRollbacksFailed += 1
            throw RollbackError.executionFailed(error.localizedDescription)
        }
    }

    // MARK: - Cleanup

    /// Rimuove un rollback point dopo verify pass (§5.6 step 8).
    public func cleanup(rollbackPoint: RollbackPoint) async throws {
        do {
            switch rollbackPoint.strategy {
            case .gitBranch:
                if let branch = rollbackPoint.branchName {
                    try await delegate.deleteBranch(name: branch)
                }
            case .gitStash:
                if let sid = rollbackPoint.stashId {
                    try await delegate.stashDrop(stashId: sid)
                }
            case .filesystemSnapshot:
                if let dir = rollbackPoint.snapshotDir {
                    try await delegate.deleteDirectory(dir: dir)
                }
            }

            activePoints.removeValue(forKey: rollbackPoint.rollbackId)
            totalCleanups += 1
        } catch {
            throw RollbackError.cleanupFailed(error.localizedDescription)
        }
    }

    // MARK: - Verify Checksums

    /// Verifica che i file siano tornati allo stato pre-apply (§5.7).
    private func verifyChecksums(
        rollbackPoint: RollbackPoint
    ) async throws -> Bool {
        for (file, expectedChecksum) in rollbackPoint.checksums {
            let actual = try await delegate.computeChecksum(file: file)
            if actual != expectedChecksum {
                throw RollbackError.checksumMismatch(
                    file: file,
                    expected: expectedChecksum,
                    actual: actual
                )
            }
        }
        return true
    }

    // MARK: - Query

    /// Restituisce un rollback point attivo per ID.
    public func activePoint(id: String) -> RollbackPoint? {
        activePoints[id]
    }

    /// Numero di rollback point attivi.
    public var activePointCount: Int {
        activePoints.count
    }

    // MARK: - Path Validation

    private func validatedPatchIdComponent(_ patchId: String) throws -> String {
        if patchId.isEmpty || patchId == "." || patchId == ".."
            || patchId.contains("/") || patchId.contains("\\")
        {
            throw RollbackError.executionFailed(
                "Invalid patchId for filesystem snapshot"
            )
        }
        return patchId
    }

    private func validatedRelativeFilePath(_ path: String) throws -> String {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") {
            throw RollbackError.executionFailed(
                "Invalid file path for rollback: \(path)"
            )
        }

        let components = NSString(string: path).pathComponents
        if components.contains("..") || components.contains(".") {
            throw RollbackError.executionFailed(
                "Invalid file path for rollback: \(path)"
            )
        }

        return path
    }

    private func validatedSnapshotDirectory(_ dir: String) throws -> String {
        let validated = try validatedRelativeFilePath(dir)
        guard validated.hasPrefix("artifacts/rollback/") else {
            throw RollbackError.executionFailed(
                "Invalid snapshot directory for rollback"
            )
        }
        return validated
    }
}
