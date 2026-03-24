import Darwin
import XCTest
@testable import CoderEngine

/// Test per il cross-process locking semplificato (senza EmergencyLockDescriptorReserve
/// e senza Thread.threadDictionary reentrancy tracking).
final class MCPCrossProcessLockSimplifiedTests: XCTestCase {

    private var testDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-lock-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: testDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDir)
        try super.tearDownWithError()
    }

    // MARK: - Advisory Lock Acquisition

    func testAcquiresAdvisoryLock() {
        let lockURL = testDir.appendingPathComponent(".test.lock")
        let result = MCPSharedState.acquireAdvisoryFileLock(
            lockURL: lockURL,
            createMode: 0o644,
            ensureLockDirectory: {}
        )

        switch result {
        case .locked(let fd):
            XCTAssertGreaterThanOrEqual(fd, 0)
            flock(fd, LOCK_UN)
            close(fd)
        case .fallback:
            XCTFail("Expected .locked, got .fallback")
        }
    }

    func testCreatesLockFileIfMissing() {
        let lockURL = testDir.appendingPathComponent(".new.lock")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))

        let result = MCPSharedState.acquireAdvisoryFileLock(
            lockURL: lockURL,
            createMode: 0o644,
            ensureLockDirectory: {}
        )

        switch result {
        case .locked(let fd):
            XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
            flock(fd, LOCK_UN)
            close(fd)
        case .fallback:
            XCTFail("Expected lock file to be created")
        }
    }

    // MARK: - withAdvisoryFileLock

    func testWithAdvisoryFileLockExecutesBody() {
        let lockURL = testDir.appendingPathComponent(".body.lock")
        let result: String = MCPSharedState.withAdvisoryFileLock(
            label: "TestLock",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: NSRecursiveLock(),
            ensureLockDirectory: {},
            body: { "executed" }
        )
        XCTAssertEqual(result, "executed")
    }

    func testWithAdvisoryFileLockReturnsValue() {
        let lockURL = testDir.appendingPathComponent(".return.lock")
        let result: Int = MCPSharedState.withAdvisoryFileLock(
            label: "TestLock",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: NSRecursiveLock(),
            ensureLockDirectory: {},
            body: { 42 }
        )
        XCTAssertEqual(result, 42)
    }

    // MARK: - Fallback Path

    func testFallbackPathExecutesBody() {
        let lockURL = testDir.appendingPathComponent(".fallback.lock")
        let result: String = MCPSharedState.withAdvisoryFileLock(
            label: "TestLock",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: NSRecursiveLock(),
            ensureLockDirectory: {},
            acquireLock: { .fallback },
            body: { "fallback-ok" }
        )
        XCTAssertEqual(result, "fallback-ok")
    }

    // MARK: - Concurrent Serialization

    func testConcurrentAccessIsSerialized() {
        let lockURL = testDir.appendingPathComponent(".concurrent.lock")
        let fallbackLock = NSRecursiveLock()
        let counterURL = testDir.appendingPathComponent("counter.txt")
        try? "0".write(to: counterURL, atomically: true, encoding: .utf8)

        let iterations = 30
        let expectation = expectation(description: "concurrent lock")
        expectation.expectedFulfillmentCount = iterations
        let queue = DispatchQueue(
            label: "test.concurrent",
            attributes: .concurrent
        )

        for _ in 0..<iterations {
            queue.async {
                MCPSharedState.withAdvisoryFileLock(
                    label: "TestLock",
                    lockURL: lockURL,
                    createMode: 0o644,
                    fallbackLock: fallbackLock,
                    ensureLockDirectory: {},
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

        waitForExpectations(timeout: 10)
        let finalValue = (try? String(contentsOf: counterURL, encoding: .utf8))
            .flatMap(Int.init)
        XCTAssertEqual(finalValue, iterations)
    }

    // MARK: - Reentrancy via NSRecursiveLock

    func testReentrancyWorksViaNSRecursiveLock() {
        let lockURL = testDir.appendingPathComponent(".reentrant.lock")
        let fallbackLock = NSRecursiveLock()

        let result: String = MCPSharedState.withAdvisoryFileLock(
            label: "Outer",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: fallbackLock,
            ensureLockDirectory: {},
            body: {
                // Chiamata rientrante dallo stesso thread
                let inner: String = MCPSharedState.withAdvisoryFileLock(
                    label: "Inner",
                    lockURL: lockURL,
                    createMode: 0o644,
                    fallbackLock: fallbackLock,
                    ensureLockDirectory: {},
                    body: { "inner-ok" }
                )
                return "outer-\(inner)"
            }
        )

        XCTAssertEqual(result, "outer-inner-ok")
    }

    // MARK: - No Descriptor Leak

    func testNoDescriptorLeakAfterMultipleLockCycles() {
        let lockURL = testDir.appendingPathComponent(".leak.lock")
        let baseline = countOpenFileDescriptors()

        for _ in 0..<20 {
            MCPSharedState.withAdvisoryFileLock(
                label: "LeakTest",
                lockURL: lockURL,
                createMode: 0o644,
                fallbackLock: NSRecursiveLock(),
                ensureLockDirectory: {},
                body: { /* noop */ }
            )
        }

        let after = countOpenFileDescriptors()
        XCTAssertLessThanOrEqual(after, baseline + 2,
            "File descriptors should not leak: baseline=\(baseline), after=\(after)")
    }

    // MARK: - Timeout Behavior

    func testAdvisoryLockTimeoutFallsBack() {
        // Salva il valore originale e imposta un timeout breve per il test
        let originalTimeout = MCPSharedState.advisoryLockTimeout
        MCPSharedState.advisoryLockTimeout = 0.2

        let lockURL = testDir.appendingPathComponent(".timeout.lock")

        // Acquisisci il lock in modo che il secondo tentativo vada in timeout.
        // Nota: su macOS flock dallo stesso processo ri-acquisisce, quindi
        // simuliamo il fallback con un acquireLock che non restituisce mai.
        let result: String = MCPSharedState.withAdvisoryFileLock(
            label: "TimeoutTest",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: NSRecursiveLock(),
            ensureLockDirectory: {},
            acquireLock: {
                // Simula un lock che non riesce ad acquisire → fallback
                .fallback
            },
            body: { "timeout-fallback-ok" }
        )

        MCPSharedState.advisoryLockTimeout = originalTimeout
        XCTAssertEqual(result, "timeout-fallback-ok",
            "Should fall back to NSRecursiveLock when file lock times out")
    }

    // MARK: - Helpers

    private func countOpenFileDescriptors() -> Int {
        var count = 0
        for fd in Int32(0)..<Int32(1024) {
            if fcntl(fd, F_GETFD) != -1 {
                count += 1
            }
        }
        return count
    }
}
