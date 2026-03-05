import Foundation

// MARK: - RollbackReference

/// Riferimento a un rollback point creato prima dell'apply (§13.1).
public struct RollbackReference: Sendable, Equatable {
    public let id: String
    public let patchId: String
    public let strategy: RollbackStrategy
    public let files: [String]
    public let checksums: [String: String]
    public let branchName: String?
    public let stashId: String?
    public let snapshotDir: String?
    public let createdAt: Date

    public init(
        id: String,
        patchId: String,
        strategy: RollbackStrategy,
        files: [String],
        checksums: [String: String] = [:],
        branchName: String? = nil,
        stashId: String? = nil,
        snapshotDir: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
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

// MARK: - RollbackServiceError

public enum RollbackServiceError: Error, Sendable, Equatable {
    case snapshotCreationFailed(reason: String)
    case rollbackExecutionFailed(reason: String)
    case checksumMismatch(file: String, expected: String, actual: String)
    case rollbackTimeout(elapsedMs: Int)
    case cleanupFailed(reason: String)
    case noFilesToRollback
    case unsupportedStrategy(RollbackStrategy)
}

// MARK: - RollbackServiceDelegate

/// Delegate per eseguire operazioni IO reali (git, filesystem).
/// Permette injection per testing.
public protocol RollbackServiceDelegate: Sendable {
    func computeChecksum(for file: String) async throws -> String
    func createGitBranch(name: String) async throws
    func deleteGitBranch(name: String) async throws
    func restoreFileFromBranch(branch: String, file: String) async throws
    func gitStashPush(message: String, files: [String]) async throws -> String
    func gitStashPop(stashId: String) async throws
    func gitStashDrop(stashId: String) async throws
    func copyFileToSnapshot(source: String, destination: String) async throws
    func restoreFileFromSnapshot(snapshot: String, file: String) async throws
    func deleteDirectory(_ path: String) async throws
    func fileExists(at path: String) async -> Bool
}

// MARK: - RollbackService

/// Servizio di rollback con 3 strategie concrete (§13.1).
///
/// Invarianti:
/// - rollback MUST ripristinare stato identico al pre-apply (verificato con checksum)
/// - rollback MUST completare entro 10000ms
/// - rollback failure MUST causare abort immediato del job
/// - ogni rollback MUST produrre un `RollbackRecord`
public actor RollbackService {

    private let delegate: RollbackServiceDelegate
    private let workspacePath: String
    private var records: [RollbackRecord] = []

    /// Timeout rollback in ms (§13.1 invariante 2).
    public static let rollbackTimeoutMs: Int = 10_000

    public init(delegate: RollbackServiceDelegate, workspacePath: String) {
        self.delegate = delegate
        self.workspacePath = workspacePath
    }

    // MARK: - Create Rollback Point

    /// Crea un rollback point PRIMA dell'apply (§13.1).
    public func createRollbackPoint(
        strategy: RollbackStrategy,
        patchId: String,
        files: [String]
    ) async throws -> RollbackReference {
        guard !files.isEmpty else {
            throw RollbackServiceError.noFilesToRollback
        }

        var checksums: [String: String] = [:]
        for file in files {
            if await delegate.fileExists(at: file) {
                checksums[file] = try await delegate.computeChecksum(for: file)
            }
        }

        let refId = "rollback_\(patchId)_\(UUID().uuidString.prefix(8))"

        switch strategy {
        case .gitBranch:
            return try await createGitBranchPoint(
                refId: refId, patchId: patchId,
                files: files, checksums: checksums
            )
        case .gitStash:
            return try await createGitStashPoint(
                refId: refId, patchId: patchId,
                files: files, checksums: checksums
            )
        case .filesystemSnapshot:
            return try await createSnapshotPoint(
                refId: refId, patchId: patchId,
                files: files, checksums: checksums
            )
        }
    }

    // MARK: - Execute Rollback

    /// Esegue il rollback (§5.7) e produce un `RollbackRecord`.
    public func execute(
        rollbackRef: RollbackReference,
        jobId: String,
        taskId: String
    ) async throws -> RollbackRecord {
        let startTime = Date()

        switch rollbackRef.strategy {
        case .gitBranch:
            try await executeGitBranchRollback(rollbackRef)
        case .gitStash:
            try await executeGitStashRollback(rollbackRef)
        case .filesystemSnapshot:
            try await executeSnapshotRollback(rollbackRef)
        }

        let verificationPassed = try await verifyChecksums(
            files: rollbackRef.files,
            expectedChecksums: rollbackRef.checksums
        )

        let completedAt = Date()
        let elapsedMs = Int(completedAt.timeIntervalSince(startTime) * 1000)

        let record = RollbackRecord(
            rollbackId: UUID().uuidString,
            jobId: jobId,
            taskId: taskId,
            patchId: rollbackRef.patchId,
            strategy: rollbackRef.strategy,
            rollbackRef: rollbackRef.id,
            filesRestored: rollbackRef.files,
            startedAt: startTime,
            completedAt: completedAt,
            status: verificationPassed ? .success : .failed,
            verificationPassed: verificationPassed,
            checksums: rollbackRef.checksums
        )

        records.append(record)

        if elapsedMs > Self.rollbackTimeoutMs {
            throw RollbackServiceError.rollbackTimeout(elapsedMs: elapsedMs)
        }

        if !verificationPassed {
            throw RollbackServiceError.rollbackExecutionFailed(
                reason: "Checksum verification failed after rollback"
            )
        }

        return record
    }

    // MARK: - Cleanup

    /// Cleanup del rollback point dopo apply+verify riusciti (§5.6 step 8).
    public func cleanup(rollbackRef: RollbackReference) async throws {
        switch rollbackRef.strategy {
        case .gitBranch:
            if let branch = rollbackRef.branchName {
                try await delegate.deleteGitBranch(name: branch)
            }
        case .gitStash:
            if let stashId = rollbackRef.stashId {
                try await delegate.gitStashDrop(stashId: stashId)
            }
        case .filesystemSnapshot:
            if let dir = rollbackRef.snapshotDir {
                try await delegate.deleteDirectory(dir)
            }
        }
    }

    // MARK: - Records

    /// Tutti i record di rollback registrati.
    public var allRecords: [RollbackRecord] { records }

    /// Ultimo record registrato.
    public var lastRecord: RollbackRecord? { records.last }

    /// Resetta i record (per testing).
    public func resetRecords() { records.removeAll() }

    // MARK: - Private: Strategy Implementations

    private func createGitBranchPoint(
        refId: String,
        patchId: String,
        files: [String],
        checksums: [String: String]
    ) async throws -> RollbackReference {
        let branchName = "rollback_\(patchId)"
        try await delegate.createGitBranch(name: branchName)
        return RollbackReference(
            id: refId, patchId: patchId,
            strategy: .gitBranch, files: files,
            checksums: checksums, branchName: branchName
        )
    }

    private func createGitStashPoint(
        refId: String,
        patchId: String,
        files: [String],
        checksums: [String: String]
    ) async throws -> RollbackReference {
        let stashMessage = "rollback_\(patchId)"
        let stashId = try await delegate.gitStashPush(
            message: stashMessage, files: files
        )
        return RollbackReference(
            id: refId, patchId: patchId,
            strategy: .gitStash, files: files,
            checksums: checksums, stashId: stashId
        )
    }

    private func createSnapshotPoint(
        refId: String,
        patchId: String,
        files: [String],
        checksums: [String: String]
    ) async throws -> RollbackReference {
        let snapshotDir = "\(workspacePath)/artifacts/rollback/\(patchId)"
        for file in files {
            if await delegate.fileExists(at: file) {
                let dest = "\(snapshotDir)/\(file)"
                try await delegate.copyFileToSnapshot(
                    source: file, destination: dest
                )
            }
        }
        return RollbackReference(
            id: refId, patchId: patchId,
            strategy: .filesystemSnapshot, files: files,
            checksums: checksums, snapshotDir: snapshotDir
        )
    }

    private func executeGitBranchRollback(
        _ ref: RollbackReference
    ) async throws {
        guard let branch = ref.branchName else {
            throw RollbackServiceError.rollbackExecutionFailed(
                reason: "Missing branch name for git_branch rollback"
            )
        }
        for file in ref.files {
            try await delegate.restoreFileFromBranch(
                branch: branch, file: file
            )
        }
        try await delegate.deleteGitBranch(name: branch)
    }

    private func executeGitStashRollback(
        _ ref: RollbackReference
    ) async throws {
        guard let stashId = ref.stashId else {
            throw RollbackServiceError.rollbackExecutionFailed(
                reason: "Missing stash ID for git_stash rollback"
            )
        }
        try await delegate.gitStashPop(stashId: stashId)
    }

    private func executeSnapshotRollback(
        _ ref: RollbackReference
    ) async throws {
        guard let snapshotDir = ref.snapshotDir else {
            throw RollbackServiceError.rollbackExecutionFailed(
                reason: "Missing snapshot dir for filesystem_snapshot rollback"
            )
        }
        for file in ref.files {
            try await delegate.restoreFileFromSnapshot(
                snapshot: snapshotDir, file: file
            )
        }
        try await delegate.deleteDirectory(snapshotDir)
    }

    // MARK: - Checksum Verification

    private func verifyChecksums(
        files: [String],
        expectedChecksums: [String: String]
    ) async throws -> Bool {
        for file in files {
            guard let expected = expectedChecksums[file] else { continue }
            let actual = try await delegate.computeChecksum(for: file)
            if actual != expected { return false }
        }
        return true
    }
}
