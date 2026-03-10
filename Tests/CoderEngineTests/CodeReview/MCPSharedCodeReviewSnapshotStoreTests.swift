import XCTest
import Darwin
@testable import CoderEngine

final class MCPSharedCodeReviewSnapshotStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testReadSnapshotsRebuildsFromSessionFilesWhenIndexIsCorrupted() throws {
        let snapshot = makeSnapshot(sessionId: "session-1", lastUpdatedAt: Date())
        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        try Data("not-json".utf8).write(to: MCPSharedState.codeReviewIndexFilePath, options: .atomic)

        let snapshots = MCPSharedState.readCodeReviewSnapshots(
            conversationId: snapshot.conversationId
        )

        XCTAssertEqual(snapshots.map(\.sessionId), ["session-1"])
    }

    func testLatestSessionIdUsesSnapshotTimestamps() {
        let conversationId = UUID()
        let older = makeSnapshot(
            sessionId: "session-old",
            conversationId: conversationId,
            lastUpdatedAt: Date(timeIntervalSinceNow: -60)
        )
        let newer = makeSnapshot(
            sessionId: "session-new",
            conversationId: conversationId,
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(older)
        MCPSharedState.writeCodeReviewSnapshot(newer)

        let latest = MCPSharedState.latestCodeReviewSessionId(
            conversationId: newer.conversationId
        )

        XCTAssertEqual(latest, "session-new")
    }

    func testLatestSessionIdPrefersTimestampAcrossSessionsOverMutationSequence() {
        let conversationId = UUID()
        let older = makeSnapshot(
            sessionId: "session-old",
            conversationId: conversationId,
            mutationSequence: 42,
            lastUpdatedAt: Date(timeIntervalSinceNow: -60)
        )
        let newer = makeSnapshot(
            sessionId: "session-new",
            conversationId: conversationId,
            mutationSequence: 1,
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(older)
        MCPSharedState.writeCodeReviewSnapshot(newer)

        let latest = MCPSharedState.latestCodeReviewSessionId(
            conversationId: newer.conversationId
        )
        let index = MCPSharedState.readCodeReviewIndex()

        XCTAssertEqual(latest, "session-new")
        XCTAssertEqual(index.latestSessionId, "session-new")
    }


    func testWriteSnapshotIgnoresInvalidSessionId() {
        let snapshot = makeSnapshot(sessionId: "../escape", lastUpdatedAt: Date())

        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: MCPSharedState.codeReviewSessionFilePath(sessionId: "../escape").path)
        )
        XCTAssertTrue(MCPSharedState.readCodeReviewSnapshots().isEmpty)
    }

    func testWriteSnapshotIgnoresOlderMutationSequence() {
        let conversationId = UUID()
        let newer = makeSnapshot(
            sessionId: "session-ordered",
            conversationId: conversationId,
            lastUpdatedAt: Date()
        )
        let older = CodeReviewSessionSnapshot(
            sessionId: newer.sessionId,
            conversationId: newer.conversationId,
            mutationSequence: newer.mutationSequence - 1,
            phase: .failed,
            stage: .failed,
            findings: [],
            events: [],
            config: .default,
            scope: newer.scope,
            workspacePath: newer.workspacePath,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: newer.startedAt,
            completedAt: Date(),
            analysisCompletedAt: newer.analysisCompletedAt,
            lastError: "stale",
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date(timeIntervalSinceNow: 60)
        )

        MCPSharedState.writeCodeReviewSnapshot(newer)
        MCPSharedState.writeCodeReviewSnapshot(older)

        let loaded = MCPSharedState.readCodeReviewSnapshot(sessionId: newer.sessionId)
        XCTAssertEqual(loaded?.phase, .fixing)
        XCTAssertEqual(loaded?.mutationSequence, newer.mutationSequence)
    }

    func testWithCodeReviewFileLockFallsBackToLocalLockWhenFileLockFails() {
        let lockURL = MCPSharedState.codeReviewDirectoryPath.appendingPathComponent(".lock")
        let result: String = MCPSharedState.withAdvisoryFileLock(
            label: "CodeReviewLockTest",
            lockURL: lockURL,
            createMode: S_IRUSR | S_IWUSR,
            fallbackLock: NSRecursiveLock(),
            ensureLockDirectory: {
                MCPSharedState.ensureDirectory()
                try? FileManager.default.createDirectory(
                    at: MCPSharedState.codeReviewDirectoryPath,
                    withIntermediateDirectories: true
                )
            },
            acquireLock: {
                .fallback(ENOENT)
            },
            body: {
                "ok"
            }
        )

        XCTAssertEqual(result, "ok")
        XCTAssertTrue(FileManager.default.fileExists(atPath: MCPSharedState.codeReviewDirectoryPath.path))
    }

    func testCodeReviewFallbackLockSerializesConcurrentWrites() {
        let lockURL = MCPSharedState.codeReviewDirectoryPath.appendingPathComponent(".lock")
        let fallbackLock = NSRecursiveLock()
        let counterURL = MCPSharedState.codeReviewDirectoryPath.appendingPathComponent("fallback_counter.txt")
        try? FileManager.default.createDirectory(
            at: MCPSharedState.codeReviewDirectoryPath,
            withIntermediateDirectories: true
        )
        try? "0".write(to: counterURL, atomically: true, encoding: .utf8)

        let iterations = 40
        let expectation = expectation(description: "code review fallback lock")
        expectation.expectedFulfillmentCount = iterations
        let queue = DispatchQueue(label: "test.codereview.fallback", attributes: .concurrent)

        for _ in 0..<iterations {
            queue.async {
                MCPSharedState.withAdvisoryFileLock(
                    label: "CodeReviewLockTest",
                    lockURL: lockURL,
                    createMode: S_IRUSR | S_IWUSR,
                    fallbackLock: fallbackLock,
                    ensureLockDirectory: {
                        MCPSharedState.ensureDirectory()
                        try? FileManager.default.createDirectory(
                            at: MCPSharedState.codeReviewDirectoryPath,
                            withIntermediateDirectories: true
                        )
                    },
                    acquireLock: {
                        .fallback(EMFILE)
                    },
                    body: {
                        let current = (try? String(contentsOf: counterURL, encoding: .utf8))
                            .flatMap(Int.init) ?? 0
                        try? String(current + 1).write(
                            to: counterURL,
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                )
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 15)
        let finalValue = (try? String(contentsOf: counterURL, encoding: .utf8))
            .flatMap(Int.init)
        XCTAssertEqual(finalValue, iterations)
    }

    func testCodeReviewFallbackAndAdvisoryPathsShareSameCriticalSection() {
        let lockURL = MCPSharedState.codeReviewDirectoryPath.appendingPathComponent(".lock")
        let fallbackLock = NSRecursiveLock()
        let queue = DispatchQueue(label: "test.codereview.mixed-locks", attributes: .concurrent)
        let stateLock = NSLock()
        var activeCriticalSections = 0
        var maxConcurrentCriticalSections = 0

        let fallbackEntered = expectation(description: "fallback path entered critical section")
        let completed = expectation(description: "mixed lock paths completed")
        completed.expectedFulfillmentCount = 2

        queue.async {
            MCPSharedState.withAdvisoryFileLock(
                label: "CodeReviewLockTest",
                lockURL: lockURL,
                createMode: S_IRUSR | S_IWUSR,
                fallbackLock: fallbackLock,
                ensureLockDirectory: {
                    MCPSharedState.ensureDirectory()
                    try? FileManager.default.createDirectory(
                        at: MCPSharedState.codeReviewDirectoryPath,
                        withIntermediateDirectories: true
                    )
                },
                acquireLock: {
                    .fallback(EMFILE)
                },
                body: {
                    stateLock.lock()
                    activeCriticalSections += 1
                    maxConcurrentCriticalSections = max(
                        maxConcurrentCriticalSections,
                        activeCriticalSections
                    )
                    stateLock.unlock()
                    fallbackEntered.fulfill()
                    Thread.sleep(forTimeInterval: 0.1)
                    stateLock.lock()
                    activeCriticalSections -= 1
                    stateLock.unlock()
                }
            )
            completed.fulfill()
        }

        wait(for: [fallbackEntered], timeout: 1.0)

        queue.async {
            MCPSharedState.withAdvisoryFileLock(
                label: "CodeReviewLockTest",
                lockURL: lockURL,
                createMode: S_IRUSR | S_IWUSR,
                fallbackLock: fallbackLock,
                ensureLockDirectory: {
                    MCPSharedState.ensureDirectory()
                    try? FileManager.default.createDirectory(
                        at: MCPSharedState.codeReviewDirectoryPath,
                        withIntermediateDirectories: true
                    )
                },
                body: {
                    stateLock.lock()
                    activeCriticalSections += 1
                    maxConcurrentCriticalSections = max(
                        maxConcurrentCriticalSections,
                        activeCriticalSections
                    )
                    stateLock.unlock()
                    Thread.sleep(forTimeInterval: 0.02)
                    stateLock.lock()
                    activeCriticalSections -= 1
                    stateLock.unlock()
                }
            )
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(maxConcurrentCriticalSections, 1)
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID = UUID(),
        mutationSequence: UInt64 = 3,
        lastUpdatedAt: Date
    ) -> CodeReviewSessionSnapshot {
        return CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence,
            phase: .fixing,
            stage: .fixing,
            findings: [
                CodeReviewFinding(
                    id: "f123",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Package.swift",
                    message: "Test finding"
                )
            ],
            events: [.sessionStarted(scope: "uncommitted changes", fileCount: 1)],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Package.swift"]),
            workspacePath: FileManager.default.currentDirectoryPath,
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
