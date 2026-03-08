import XCTest
@testable import CoderEngine

final class PipelineLockManagerTests: XCTestCase {

    // MARK: - LockScope

    func testLockScopeAllKeys() {
        let scope = LockScope(
            files: ["a.swift", "b.swift"],
            symbols: ["MyClass"]
        )
        XCTAssertEqual(scope.allKeys, ["a.swift", "b.swift", "MyClass"])
    }

    func testLockScopeOverlap() {
        let s1 = LockScope(files: ["a.swift"], symbols: ["Foo"])
        let s2 = LockScope(files: ["b.swift"], symbols: ["Foo"])
        XCTAssertTrue(s1.overlaps(with: s2))
    }

    func testLockScopeNoOverlap() {
        let s1 = LockScope(files: ["a.swift"], symbols: ["Foo"])
        let s2 = LockScope(files: ["b.swift"], symbols: ["Bar"])
        XCTAssertFalse(s1.overlaps(with: s2))
    }

    func testLockScopeFromTask() {
        let task = TaskNode(
            taskId: "T1",
            title: "Test",
            fileScope: ["a.swift", "b.swift"],
            symbolScope: ["MyClass"]
        )
        let scope = LockScope(from: task)
        XCTAssertEqual(scope.files, ["a.swift", "b.swift"])
        XCTAssertEqual(scope.symbols, ["MyClass"])
    }

    // MARK: - Acquire / Release

    func testAcquireAndRelease() async {
        let mgr = PipelineLockManager()
        let scope = LockScope(files: ["a.swift"])

        let acquired = await mgr.acquire(scope: scope, taskId: "T1")
        XCTAssertTrue(acquired)

        let owners = await mgr.activeLockOwners
        XCTAssertTrue(owners.contains("T1"))

        await mgr.release(taskId: "T1")
        let ownersAfter = await mgr.activeLockOwners
        XCTAssertFalse(ownersAfter.contains("T1"))
    }

    func testEmptyScopeAlwaysSucceeds() async {
        let mgr = PipelineLockManager()
        let scope = LockScope()
        let acquired = await mgr.acquire(scope: scope, taskId: "T1")
        XCTAssertTrue(acquired)
    }

    // MARK: - Verify Ownership

    func testVerifyOwnershipTrue() async {
        let mgr = PipelineLockManager()
        let scope = LockScope(files: ["a.swift", "b.swift"], symbols: ["Foo"])
        _ = await mgr.acquire(scope: scope, taskId: "T1")

        let verified = await mgr.verifyOwnership(
            files: ["a.swift", "Foo"],
            taskId: "T1"
        )
        XCTAssertTrue(verified)
    }

    func testVerifyOwnershipFalseNoLock() async {
        let mgr = PipelineLockManager()
        let verified = await mgr.verifyOwnership(
            files: ["a.swift"],
            taskId: "T_NONE"
        )
        XCTAssertFalse(verified)
    }

    // MARK: - Total Locked Keys

    func testTotalLockedKeys() async {
        let mgr = PipelineLockManager()
        _ = await mgr.acquire(
            scope: LockScope(files: ["a.swift", "b.swift"], symbols: ["Foo"]),
            taskId: "T1"
        )
        let total = await mgr.totalLockedKeys
        XCTAssertEqual(total, 3)
    }

    // MARK: - Reset

    func testResetClearsAll() async {
        let mgr = PipelineLockManager()
        _ = await mgr.acquire(
            scope: LockScope(files: ["a.swift"]),
            taskId: "T1"
        )
        await mgr.reset()

        let owners = await mgr.activeLockOwners
        XCTAssertTrue(owners.isEmpty)
        let total = await mgr.totalLockedKeys
        XCTAssertEqual(total, 0)
    }
}
