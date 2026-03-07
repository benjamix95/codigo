import XCTest
@testable import CoderEngine

// MARK: - Mock Delegate

private actor MockRollbackDelegate: RollbackServiceDelegate {
    var createdBranches: [String] = []
    var deletedBranches: [String] = []
    var restoredFiles: [(branch: String, file: String)] = []
    var stashPushCalls: [(message: String, files: [String])] = []
    var stashPopCalls: [String] = []
    var stashDropCalls: [String] = []
    var copiedSnapshots: [(files: [String], dir: String)] = []
    var restoredSnapshots: [(dir: String, file: String)] = []
    var deletedDirs: [String] = []
    var checksums: [String: String] = [:]
    var existingFiles: Set<String> = []

    var shouldFailOnApply = false
    var shouldFailOnRestore = false
    var checksumAfterRestore: [String: String] = [:]

    func configure(
        checksums: [String: String],
        existingFiles: Set<String>
    ) {
        self.checksums = checksums
        self.existingFiles = existingFiles
        self.checksumAfterRestore = checksums
    }

    func setChecksumAfterRestore(_ map: [String: String]) {
        self.checksumAfterRestore = map
    }

    func setShouldFailOnRestore(_ val: Bool) {
        self.shouldFailOnRestore = val
    }

    nonisolated func createBranch(name: String) async throws {
        await _addCreatedBranch(name)
    }

    private func _addCreatedBranch(_ name: String) {
        createdBranches.append(name)
    }

    nonisolated func switchToBranch(name: String) async throws {}

    nonisolated func deleteBranch(name: String) async throws {
        await _addDeletedBranch(name)
    }

    private func _addDeletedBranch(_ name: String) {
        deletedBranches.append(name)
    }

    nonisolated func restoreFileFromBranch(
        branch: String, file: String
    ) async throws {
        let fail = await _shouldFailOnRestore()
        if fail { throw RollbackError.fileNotFound(file) }
        await _addRestoredFile(branch: branch, file: file)
    }

    private func _shouldFailOnRestore() -> Bool { shouldFailOnRestore }

    private func _addRestoredFile(branch: String, file: String) {
        restoredFiles.append((branch, file))
    }

    nonisolated func stashPush(
        message: String, files: [String]
    ) async throws -> String {
        await _addStashPush(message: message, files: files)
        return "stash@{0}"
    }

    private func _addStashPush(message: String, files: [String]) {
        stashPushCalls.append((message, files))
    }

    nonisolated func stashPop(stashId: String) async throws {
        await _addStashPop(stashId)
    }

    private func _addStashPop(_ id: String) {
        stashPopCalls.append(id)
    }

    nonisolated func stashDrop(stashId: String) async throws {
        await _addStashDrop(stashId)
    }

    private func _addStashDrop(_ id: String) {
        stashDropCalls.append(id)
    }

    nonisolated func copyFilesToSnapshot(
        files: [String], dir: String
    ) async throws {
        await _addCopiedSnapshot(files: files, dir: dir)
    }

    private func _addCopiedSnapshot(files: [String], dir: String) {
        copiedSnapshots.append((files, dir))
    }

    nonisolated func restoreFileFromSnapshot(
        snapshotDir: String, file: String
    ) async throws {
        await _addRestoredSnapshot(dir: snapshotDir, file: file)
    }

    private func _addRestoredSnapshot(dir: String, file: String) {
        restoredSnapshots.append((dir, file))
    }

    nonisolated func deleteDirectory(dir: String) async throws {
        await _addDeletedDir(dir)
    }

    private func _addDeletedDir(_ dir: String) {
        deletedDirs.append(dir)
    }

    nonisolated func computeChecksum(file: String) async throws -> String {
        let cs = await _checksum(for: file)
        return cs ?? "unknown"
    }

    private func _checksum(for file: String) -> String? {
        checksumAfterRestore[file] ?? checksums[file]
    }

    nonisolated func fileExists(path: String) async -> Bool {
        await _fileExists(path)
    }

    private func _fileExists(_ path: String) -> Bool {
        existingFiles.contains(path)
    }
}

// MARK: - Tests

final class RollbackServiceTests: XCTestCase {

    private func makeService() -> (RollbackService, MockRollbackDelegate) {
        let delegate = MockRollbackDelegate()
        let service = RollbackService(delegate: delegate)
        return (service, delegate)
    }

    // MARK: - Create Rollback Point

    func testCreateRollbackPoint_gitBranch() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "abc123"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1",
            strategy: .gitBranch,
            files: ["a.swift"]
        )

        XCTAssertEqual(point.strategy, .gitBranch)
        XCTAssertEqual(point.branchName, "rollback_p1")
        XCTAssertEqual(point.files, ["a.swift"])
        XCTAssertEqual(point.checksums["a.swift"], "abc123")
        XCTAssertNil(point.stashId)
        XCTAssertNil(point.snapshotDir)
        let created = await service.totalRollbacksCreated
        XCTAssertEqual(created, 1)
    }

    func testCreateRollbackPoint_gitStash() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["b.swift": "def456"],
            existingFiles: ["b.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p2",
            strategy: .gitStash,
            files: ["b.swift"]
        )

        XCTAssertEqual(point.strategy, .gitStash)
        XCTAssertEqual(point.stashId, "stash@{0}")
        XCTAssertNil(point.branchName)
    }

    func testCreateRollbackPoint_filesystemSnapshot() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["c.swift": "ghi789"],
            existingFiles: ["c.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p3",
            strategy: .filesystemSnapshot,
            files: ["c.swift"]
        )

        XCTAssertEqual(point.strategy, .filesystemSnapshot)
        XCTAssertEqual(point.snapshotDir, "artifacts/rollback/p3")
        XCTAssertNil(point.branchName)
    }

    // MARK: - Execute

    func testExecute_gitBranch_success() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "abc"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: ["a.swift"]
        )

        let record = try await service.execute(
            rollbackPoint: point, jobId: "j1", taskId: "t1"
        )

        XCTAssertEqual(record.status, .success)
        XCTAssertTrue(record.verificationPassed)
        XCTAssertEqual(record.strategy, .gitBranch)
        XCTAssertEqual(record.filesRestored, ["a.swift"])
        let executed = await service.totalRollbacksExecuted
        XCTAssertEqual(executed, 1)
    }

    func testExecute_gitStash_success() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "abc"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitStash, files: ["a.swift"]
        )

        let record = try await service.execute(
            rollbackPoint: point, jobId: "j1", taskId: "t1"
        )

        XCTAssertEqual(record.status, .success)
    }

    func testExecute_filesystemSnapshot_success() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "abc"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .filesystemSnapshot, files: ["a.swift"]
        )

        let record = try await service.execute(
            rollbackPoint: point, jobId: "j1", taskId: "t1"
        )

        XCTAssertEqual(record.status, .success)
    }

    func testExecute_checksumMismatch_throws() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "original"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: ["a.swift"]
        )

        await delegate.setChecksumAfterRestore(["a.swift": "different"])

        do {
            _ = try await service.execute(
                rollbackPoint: point, jobId: "j1", taskId: "t1"
            )
            XCTFail("Should have thrown")
        } catch let error as RollbackError {
            if case .checksumMismatch(let file, _, _) = error {
                XCTAssertEqual(file, "a.swift")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        let failed = await service.totalRollbacksFailed
        XCTAssertEqual(failed, 1)
    }

    func testExecute_restoreFailure_throws() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(
            checksums: ["a.swift": "abc"],
            existingFiles: ["a.swift"]
        )

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: ["a.swift"]
        )

        await delegate.setShouldFailOnRestore(true)

        do {
            _ = try await service.execute(
                rollbackPoint: point, jobId: "j1", taskId: "t1"
            )
            XCTFail("Should have thrown")
        } catch {
            let failed = await service.totalRollbacksFailed
            XCTAssertEqual(failed, 1)
        }
    }

    // MARK: - Cleanup

    func testCleanup_gitBranch() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(checksums: [:], existingFiles: [])

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: []
        )

        try await service.cleanup(rollbackPoint: point)

        let cleanups = await service.totalCleanups
        XCTAssertEqual(cleanups, 1)
        let count = await service.activePointCount
        XCTAssertEqual(count, 0)
    }

    func testCleanup_gitStash() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(checksums: [:], existingFiles: [])

        let point = try await service.createRollbackPoint(
            patchId: "p2", strategy: .gitStash, files: []
        )

        try await service.cleanup(rollbackPoint: point)

        let cleanups = await service.totalCleanups
        XCTAssertEqual(cleanups, 1)
    }

    // MARK: - Active Points

    func testActivePointTracking() async throws {
        let (service, delegate) = makeService()
        await delegate.configure(checksums: [:], existingFiles: [])

        let p1 = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: []
        )
        let _ = try await service.createRollbackPoint(
            patchId: "p2", strategy: .gitBranch, files: []
        )

        let count = await service.activePointCount
        XCTAssertEqual(count, 2)

        let found = await service.activePoint(id: p1.rollbackId)
        XCTAssertNotNil(found)
    }

    // MARK: - Non-existent file checksum

    func testCreateRollbackPoint_skipChecksumForMissingFile() async throws {
        let (service, _) = makeService()

        let point = try await service.createRollbackPoint(
            patchId: "p1", strategy: .gitBranch, files: ["nonexist.swift"]
        )

        XCTAssertTrue(point.checksums.isEmpty)
    }

    func testCreateRollbackPoint_filesystemSnapshot_rejectsTraversalPatchId() async {
        let (service, _) = makeService()

        do {
            _ = try await service.createRollbackPoint(
                patchId: "../evil", strategy: .filesystemSnapshot,
                files: ["a.swift"]
            )
            XCTFail("Should have thrown")
        } catch let error as RollbackError {
            guard case .executionFailed(let reason) = error else {
                return XCTFail("Wrong error type: \(error)")
            }
            XCTAssertTrue(reason.contains("Invalid patchId"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testCreateRollbackPoint_rejectsTraversalFilePath() async {
        let (service, _) = makeService()

        do {
            _ = try await service.createRollbackPoint(
                patchId: "p1", strategy: .filesystemSnapshot,
                files: ["../outside.txt"]
            )
            XCTFail("Should have thrown")
        } catch let error as RollbackError {
            guard case .executionFailed(let reason) = error else {
                return XCTFail("Wrong error type: \(error)")
            }
            XCTAssertTrue(reason.contains("Invalid file path"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testExecute_filesystemSnapshot_rejectsTraversalFilePath() async {
        let (service, _) = makeService()

        let point = RollbackPoint(
            rollbackId: "rb_test",
            patchId: "p1",
            strategy: .filesystemSnapshot,
            files: ["../outside.txt"],
            checksums: [:],
            snapshotDir: "artifacts/rollback/p1"
        )

        do {
            _ = try await service.execute(
                rollbackPoint: point, jobId: "j1", taskId: "t1"
            )
            XCTFail("Should have thrown")
        } catch let error as RollbackError {
            guard case .executionFailed(let reason) = error else {
                return XCTFail("Wrong error type: \(error)")
            }
            XCTAssertTrue(reason.contains("Invalid file path"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
