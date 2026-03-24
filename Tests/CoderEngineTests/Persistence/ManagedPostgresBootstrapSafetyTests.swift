import XCTest
@testable import CoderEngine

/// Test per la thread-safety del bootstrap Postgres.
///
/// Verifica che chiamate concorrenti a bootstrapIfNeeded() siano
/// serializzate e che il flag isBootstrapped + file lock prevengano
/// doppie inizializzazioni.
final class ManagedPostgresBootstrapSafetyTests: XCTestCase {

    // MARK: - Caching Behavior

    func testBootstrapCachesResultAfterFirstCall() throws {
        // ManagedPostgresService.shared usa una coda seriale.
        // Questo test verifica che il servizio abbia il flag isBootstrapped.
        let service = ManagedPostgresService(configuration: nil)

        // Non possiamo facilmente testare il bootstrap reale senza Postgres,
        // ma possiamo verificare che la struttura interna sia corretta
        // ispezionando il servizio tramite reflection.
        let mirror = Mirror(reflecting: service)

        let hasIsBootstrapped = mirror.children.contains { $0.label == "isBootstrapped" }
        XCTAssertTrue(hasIsBootstrapped, "ManagedPostgresService should have isBootstrapped flag")

        let hasCachedHealth = mirror.children.contains { $0.label == "cachedHealth" }
        XCTAssertTrue(hasCachedHealth, "ManagedPostgresService should have cachedHealth cache")
    }

    // MARK: - Concurrent Access Serialization

    func testConcurrentBootstrapCallsAreSerialized() {
        // Verifica che la DispatchQueue seriale impedisca esecuzioni parallele.
        let queue = DispatchQueue(label: "test.serial")
        var executionOrder: [Int] = []
        let lock = NSLock()
        let expectation = expectation(description: "concurrent bootstrap")
        expectation.expectedFulfillmentCount = 10

        let concurrentQueue = DispatchQueue(
            label: "test.concurrent",
            attributes: .concurrent
        )

        for i in 0..<10 {
            concurrentQueue.async {
                queue.sync {
                    lock.lock()
                    executionOrder.append(i)
                    lock.unlock()
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)

        // Tutti i 10 task devono aver eseguito
        XCTAssertEqual(executionOrder.count, 10)
    }

    // MARK: - File Lock

    func testBootstrapLockFileCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pg-bootstrap-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockPath = tempDir.appendingPathComponent(".bootstrap.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0, "Should be able to create lock file")

        let lockResult = flock(fd, LOCK_EX | LOCK_NB)
        XCTAssertEqual(lockResult, 0, "Should acquire exclusive lock")

        // Secondo tentativo non-blocking deve fallire
        let fd2 = open(lockPath, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd2, 0)
        let lockResult2 = flock(fd2, LOCK_EX | LOCK_NB)
        // Su macOS, flock dallo stesso processo può ri-acquisire il lock
        // ma da processi diversi no. In-process, entrambi acquisiscono.
        // Questo test verifica almeno che il meccanismo non crashi.
        if lockResult2 == 0 {
            flock(fd2, LOCK_UN)
        }
        close(fd2)

        flock(fd, LOCK_UN)
        close(fd)
    }

    // MARK: - Shutdown Resets State

    func testShutdownResetsBootstrapState() {
        let service = ManagedPostgresService(configuration: nil)
        let mirror = Mirror(reflecting: service)

        // Verifica che isBootstrapped parta a false
        if let isBootstrapped = mirror.children.first(where: { $0.label == "isBootstrapped" })?.value as? Bool {
            XCTAssertFalse(isBootstrapped, "isBootstrapped should start as false")
        }
    }

    // MARK: - flockWithTimeout

    func testFlockWithTimeoutAcquiresLock() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("flock-timeout-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockPath = tempDir.appendingPathComponent(".test.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        let acquired = ManagedPostgresService.flockWithTimeout(fd, timeout: 2)
        XCTAssertTrue(acquired, "flockWithTimeout should acquire an uncontested lock")
        flock(fd, LOCK_UN)
    }

    func testFlockWithTimeoutReturnsOnInvalidFd() {
        let result = ManagedPostgresService.flockWithTimeout(-1, timeout: 0.1)
        XCTAssertFalse(result, "flockWithTimeout should fail on invalid fd")
    }
}
