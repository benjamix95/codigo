import XCTest
@testable import CoderEngine

// MARK: - MockRollbackDelegate

final class MockRollbackDelegate: RollbackServiceDelegate, @unchecked Sendable {
    var checksums: [String: String] = [:]
    var existingFiles: Set<String> = []
    var createdBranches: [String] = []
    var deletedBranches: [String] = []
    var restoredFromBranch: [(branch: String, file: String)] = []
    var stashPushCalls: [(message: String, files: [String])] = []
    var stashPopCalls: [String] = []
    var stashDropCalls: [String] = []
    var copiedSnapshots: [(source: String, dest: String)] = []
    var restoredFromSnapshot: [(snapshot: String, file: String)] = []
    var deletedDirs: [String] = []
    var shouldFailChecksum = false
    var shouldFailBranchCreate = false
    var shouldFailStashPush = false
    var shouldFailRestore = false

    func computeChecksum(for file: String) async throws -> String {
        if shouldFailChecksum { throw RollbackServiceError.checksumMismatch(file: file, expected: "", actual: "") }
        return checksums[file] ?? "hash_\(file)"
    }

    func createGitBranch(name: String) async throws {
        if shouldFailBranchCreate { throw RollbackServiceError.snapshotCreationFailed(reason: "branch create failed") }
        createdBranches.append(name)
    }

    func deleteGitBranch(name: String) async throws {
        deletedBranches.append(name)
    }

    func restoreFileFromBranch(branch: String, file: String) async throws {
        if shouldFailRestore { throw RollbackServiceError.rollbackExecutionFailed(reason: "restore failed") }
        restoredFromBranch.append((branch, file))
    }

    func gitStashPush(message: String, files: [String]) async throws -> String {
        if shouldFailStashPush { throw RollbackServiceError.snapshotCreationFailed(reason: "stash push failed") }
        stashPushCalls.append((message, files))
        return "stash@{0}"
    }

    func gitStashPop(stashId: String) async throws {
        stashPopCalls.append(stashId)
    }

    func gitStashDrop(stashId: String) async throws {
        stashDropCalls.append(stashId)
    }

    func copyFileToSnapshot(source: String, destination: String) async throws {
        copiedSnapshots.append((source, destination))
    }

    func restoreFileFromSnapshot(snapshot: String, file: String) async throws {
        if shouldFailRestore { throw RollbackServiceError.rollbackExecutionFailed(reason: "snapshot restore failed") }
        restoredFromSnapshot.append((snapshot, file))
    }

    func deleteDirectory(_ path: String) async throws {
        deletedDirs.append(path)
    }

    func fileExists(at path: String) async -> Bool {
        existingFiles.contains(path)
    }
}

// MARK: - RollbackServiceTests

final class RollbackServiceTests: XCTestCase {

    var delegate: MockRollbackDelegate!

    override func setUp() {
        super.setUp()
        delegate = MockRollbackDelegate()
        delegate.existingFiles = ["a.swift", "b.swift"]
        delegate.checksums = ["a.swift": "hash_a", "b.swift": "hash_b"]
    }

    private func makeService() -> RollbackService {
        RollbackService(delegate: delegate, workspacePath: "/workspace")
    }

    // MARK: - Create Rollback Point

    func testCreateGitBranchRollbackPoint() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "patch1",
            files: ["a.swift", "b.swift"]
        )
        XCTAssertEqual(ref.strategy, .gitBranch)
        XCTAssertEqual(ref.files, ["a.swift", "b.swift"])
        XCTAssertNotNil(ref.branchName)
        XCTAssertTrue(ref.branchName?.contains("patch1") == true)
        XCTAssertEqual(ref.checksums.count, 2)
        XCTAssertEqual(delegate.createdBranches.count, 1)
    }

    func testCreateGitStashRollbackPoint() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitStash, patchId: "patch2",
            files: ["a.swift"]
        )
        XCTAssertEqual(ref.strategy, .gitStash)
        XCTAssertEqual(ref.stashId, "stash@{0}")
        XCTAssertEqual(delegate.stashPushCalls.count, 1)
    }

    func testCreateFilesystemSnapshotRollbackPoint() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .filesystemSnapshot, patchId: "patch3",
            files: ["a.swift", "b.swift"]
        )
        XCTAssertEqual(ref.strategy, .filesystemSnapshot)
        XCTAssertNotNil(ref.snapshotDir)
        XCTAssertTrue(ref.snapshotDir?.contains("patch3") == true)
        XCTAssertEqual(delegate.copiedSnapshots.count, 2)
    }

    func testCreateRollbackPointEmptyFilesThrows() async {
        let service = makeService()
        do {
            _ = try await service.createRollbackPoint(
                strategy: .gitBranch, patchId: "p", files: []
            )
            XCTFail("Should throw for empty files")
        } catch {
            guard let err = error as? RollbackServiceError,
                  case .noFilesToRollback = err else {
                XCTFail("Wrong error type: \(error)")
                return
            }
        }
    }

    func testCreateRollbackPointSkipsNonExistentFiles() async throws {
        delegate.existingFiles = ["a.swift"]
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .filesystemSnapshot, patchId: "p",
            files: ["a.swift", "nonexistent.swift"]
        )
        XCTAssertEqual(delegate.copiedSnapshots.count, 1, "Only existing file gets snapshot")
        XCTAssertEqual(ref.checksums.count, 1, "Only existing file has checksum")
    }

    // MARK: - Execute Rollback

    func testExecuteGitBranchRollback() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "p1",
            files: ["a.swift", "b.swift"]
        )
        let record = try await service.execute(
            rollbackRef: ref, jobId: "j1", taskId: "t1"
        )
        XCTAssertEqual(record.status, .success)
        XCTAssertTrue(record.verificationPassed)
        XCTAssertEqual(record.filesRestored, ["a.swift", "b.swift"])
        XCTAssertEqual(record.strategy, .gitBranch)
        XCTAssertEqual(delegate.restoredFromBranch.count, 2)
        XCTAssertEqual(delegate.deletedBranches.count, 1)
    }

    func testExecuteGitStashRollback() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitStash, patchId: "p2",
            files: ["a.swift"]
        )
        let record = try await service.execute(
            rollbackRef: ref, jobId: "j1", taskId: "t1"
        )
        XCTAssertEqual(record.status, .success)
        XCTAssertEqual(delegate.stashPopCalls.count, 1)
    }

    func testExecuteFilesystemSnapshotRollback() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .filesystemSnapshot, patchId: "p3",
            files: ["a.swift"]
        )
        let record = try await service.execute(
            rollbackRef: ref, jobId: "j1", taskId: "t1"
        )
        XCTAssertEqual(record.status, .success)
        XCTAssertEqual(delegate.restoredFromSnapshot.count, 1)
        XCTAssertEqual(delegate.deletedDirs.count, 1)
    }

    func testExecuteRollbackRecordsArePersisted() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "p",
            files: ["a.swift"]
        )
        _ = try await service.execute(
            rollbackRef: ref, jobId: "j1", taskId: "t1"
        )
        let records = await service.allRecords
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.jobId, "j1")
    }

    // MARK: - Cleanup

    func testCleanupGitBranch() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "p",
            files: ["a.swift"]
        )
        delegate.deletedBranches = []
        try await service.cleanup(rollbackRef: ref)
        XCTAssertEqual(delegate.deletedBranches.count, 1)
    }

    func testCleanupGitStash() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitStash, patchId: "p",
            files: ["a.swift"]
        )
        try await service.cleanup(rollbackRef: ref)
        XCTAssertEqual(delegate.stashDropCalls.count, 1)
    }

    func testCleanupFilesystemSnapshot() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .filesystemSnapshot, patchId: "p",
            files: ["a.swift"]
        )
        delegate.deletedDirs = []
        try await service.cleanup(rollbackRef: ref)
        XCTAssertEqual(delegate.deletedDirs.count, 1)
    }

    // MARK: - Checksum Verification Failure

    func testChecksumMismatchReturnsFailedRecord() async throws {
        delegate.checksums = ["a.swift": "original"]
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "p",
            files: ["a.swift"]
        )
        delegate.checksums = ["a.swift": "modified_after_rollback"]
        do {
            _ = try await service.execute(
                rollbackRef: ref, jobId: "j1", taskId: "t1"
            )
            XCTFail("Should throw for checksum mismatch")
        } catch {
            let records = await service.allRecords
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.status, .failed)
            XCTAssertFalse(records.first?.verificationPassed ?? true)
        }
    }

    // MARK: - Reset Records

    func testResetRecords() async throws {
        let service = makeService()
        let ref = try await service.createRollbackPoint(
            strategy: .gitBranch, patchId: "p",
            files: ["a.swift"]
        )
        _ = try await service.execute(
            rollbackRef: ref, jobId: "j1", taskId: "t1"
        )
        await service.resetRecords()
        let records = await service.allRecords
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Branch Create Failure

    func testBranchCreateFailureThrows() async {
        delegate.shouldFailBranchCreate = true
        let service = makeService()
        do {
            _ = try await service.createRollbackPoint(
                strategy: .gitBranch, patchId: "p",
                files: ["a.swift"]
            )
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error is RollbackServiceError)
        }
    }
}
