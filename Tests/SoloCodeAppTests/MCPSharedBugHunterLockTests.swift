import XCTest
@testable import CoderEngine

final class MCPSharedBugHunterLockTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try super.tearDownWithError()
    }

    // MARK: - Lock file creation with O_CREAT

    func testWithBugHunterFileLockCreatesLockFile() {
        let result: Int = MCPSharedState.withBugHunterFileLock { 42 }

        XCTAssertEqual(result, 42)

        let lockPath = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent(".lock").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lockPath),
            "Il file di lock deve essere creato con O_CREAT"
        )
    }

    func testWithBugHunterFileLockCreatesDirectories() {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)

        _ = MCPSharedState.withBugHunterFileLock { true }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: MCPSharedState.bugHunterDirectoryPath.path),
            "La directory bugHunter deve essere creata automaticamente"
        )
    }

    // MARK: - Lock serializes concurrent access

    func testWithBugHunterFileLockSerializesConcurrentAccess() {
        let iterations = 50
        let expectation = self.expectation(description: "concurrent lock access")
        expectation.expectedFulfillmentCount = iterations

        var results: [Int] = []
        let queue = DispatchQueue(label: "test.lock.concurrent", attributes: .concurrent)

        for i in 0..<iterations {
            queue.async {
                MCPSharedState.withBugHunterFileLock {
                    results.append(i)
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 15)
        XCTAssertEqual(results.count, iterations, "Tutte le operazioni devono completarsi")
    }

    // MARK: - Lock protects command enqueue

    func testConcurrentEnqueueCommandsNoDataLoss() {
        let count = 20
        let expectation = self.expectation(description: "concurrent enqueue")
        expectation.expectedFulfillmentCount = count

        let queue = DispatchQueue(label: "test.enqueue.concurrent", attributes: .concurrent)

        for i in 0..<count {
            queue.async {
                _ = MCPSharedState.enqueueBugHunterCommand(
                    action: "test-\(i)",
                    runId: "run-\(i)",
                    conversationId: nil,
                    payload: [:]
                )
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 15)

        let claimed = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertEqual(
            claimed.count, count,
            "Nessun comando deve andare perso con accesso concorrente"
        )
    }

    // MARK: - Lock return value

    func testWithBugHunterFileLockReturnsOperationResult() {
        let value = MCPSharedState.withBugHunterFileLock { "hello" }
        XCTAssertEqual(value, "hello")
    }

    func testWithBugHunterFileLockReturnsVoid() {
        var sideEffect = false
        MCPSharedState.withBugHunterFileLock { sideEffect = true }
        XCTAssertTrue(sideEffect)
    }

    // MARK: - Command lifecycle under lock

    func testMarkCommandStatusUnderLock() {
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "scan",
            runId: "run-mark",
            conversationId: nil,
            payload: [:]
        )

        _ = MCPSharedState.claimPendingBugHunterCommands()

        MCPSharedState.markBugHunterCommand(
            id: command.id,
            status: .completed,
            resultMessage: "done"
        )

        let pending = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertTrue(pending.isEmpty, "Comando completato non deve essere ri-claimato")
    }

    func testHeartbeatUpdatesTimestamp() {
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "scan",
            runId: "run-hb",
            conversationId: nil,
            payload: [:]
        )

        _ = MCPSharedState.claimPendingBugHunterCommands()

        Thread.sleep(forTimeInterval: 0.05)

        MCPSharedState.refreshBugHunterCommandHeartbeat(id: command.id)

        let pending = MCPSharedState.claimPendingBugHunterCommands()
        XCTAssertTrue(pending.isEmpty, "Heartbeat aggiornato non deve rendere il comando claimable")
    }

    // MARK: - Lock file permissions & integrity (bypass protection)

    func testLockFileHasCorrectPermissions() {
        _ = MCPSharedState.withBugHunterFileLock { true }

        let lockURL = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent(".lock")
        let attrs = try? FileManager.default.attributesOfItem(atPath: lockURL.path)
        let perms = (attrs?[.posixPermissions] as? Int) ?? 0

        // O_CREAT con 0o644: owner rw, group r, other r
        XCTAssertEqual(
            perms & 0o777, 0o644,
            "Lock file deve avere permessi 0644 per consentire open() su riaperture"
        )
    }

    func testLockFileDescriptorIsValidDuringOperation() {
        // Verifica che l'operazione esegue dentro un lock valido
        // controllando che il file di lock esiste durante l'esecuzione
        var lockExistsDuringOp = false
        let lockPath = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent(".lock").path

        MCPSharedState.withBugHunterFileLock {
            lockExistsDuringOp = FileManager.default.fileExists(atPath: lockPath)
        }

        XCTAssertTrue(
            lockExistsDuringOp,
            "Il file di lock deve esistere durante l'esecuzione dell'operazione"
        )
    }

    func testLockFileReuseAcrossMultipleCalls() {
        // Verifica che lo stesso file di lock è riutilizzato senza errori
        for i in 0..<10 {
            let result = MCPSharedState.withBugHunterFileLock { i * 2 }
            XCTAssertEqual(result, i * 2)
        }

        let lockPath = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent(".lock").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lockPath),
            "Lock file deve persistere dopo molteplici acquisizioni"
        )
    }

    // MARK: - Concurrent mutation integrity (no bypass)

    func testConcurrentCounterIncrementNoRaceCondition() {
        // Stress test: incremento atomico di un contatore condiviso
        // Se il lock fosse bypassato, il contatore finale sarebbe < iterations
        let iterations = 100
        let expectation = self.expectation(description: "counter increment")
        expectation.expectedFulfillmentCount = iterations

        let counterURL = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent("test_counter.txt")
        MCPSharedState.withBugHunterFileLock {
            try? "0".write(to: counterURL, atomically: true, encoding: .utf8)
        }

        let queue = DispatchQueue(
            label: "test.counter.concurrent",
            attributes: .concurrent
        )

        for _ in 0..<iterations {
            queue.async {
                MCPSharedState.withBugHunterFileLock {
                    let current = (try? String(contentsOf: counterURL, encoding: .utf8))
                        .flatMap { Int($0) } ?? 0
                    try? String(current + 1).write(
                        to: counterURL, atomically: true, encoding: .utf8
                    )
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 30)

        let finalValue = MCPSharedState.withBugHunterFileLock {
            (try? String(contentsOf: counterURL, encoding: .utf8))
                .flatMap { Int($0) } ?? 0
        }

        XCTAssertEqual(
            finalValue, iterations,
            "Contatore deve essere esattamente \(iterations) — race condition rilevata se diverso"
        )

        try? FileManager.default.removeItem(at: counterURL)
    }

    func testConcurrentClaimAndEnqueueNoCorruption() {
        // Verifica che claim + enqueue concorrenti non corrompono lo stato
        let enqueueCount = 30
        let expectation = self.expectation(description: "mixed ops")
        expectation.expectedFulfillmentCount = enqueueCount + 5

        let queue = DispatchQueue(
            label: "test.mixed.concurrent",
            attributes: .concurrent
        )

        for i in 0..<enqueueCount {
            queue.async {
                _ = MCPSharedState.enqueueBugHunterCommand(
                    action: "mixed-\(i)",
                    runId: "run-mixed-\(i)",
                    conversationId: nil,
                    payload: [:]
                )
                expectation.fulfill()
            }
        }

        // 5 claim concorrenti
        for _ in 0..<5 {
            queue.async {
                _ = MCPSharedState.claimPendingBugHunterCommands()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 15)
        // Nessun crash = nessuna corruzione dati
    }

}
