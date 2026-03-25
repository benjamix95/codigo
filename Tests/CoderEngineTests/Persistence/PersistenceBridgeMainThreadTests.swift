import XCTest
@testable import CoderEngine

/// Test di regressione per il crash EXC_BREAKPOINT quando
/// `bootstrapIfNeeded()` veniva chiamato dal main thread.
///
/// La causa era `dispatchPrecondition(condition: .notOnQueue(.main))` in
/// `ManagedPostgresService.bootstrapIfNeeded()`. La funzione è internamente
/// thread-safe (usa queue.sync su coda custom separata), quindi la precondition
/// era una guardia eccessiva che causava crash in DEBUG.
final class PersistenceBridgeMainThreadTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        PersistenceTestSupport.resetPersistenceEnvironment()
        PersistenceTestSupport.enablePersistenceForTests()
    }

    override func tearDownWithError() throws {
        PersistenceTestSupport.resetPersistenceEnvironment()
        try super.tearDownWithError()
    }

    // MARK: - Regression: EXC_BREAKPOINT on main thread

    func testBootstrapIfNeededDoesNotCrashOnMainThread() {
        // XCTest gira sul main thread. Prima del fix, questa chiamata
        // causava EXC_BREAKPOINT per via del dispatchPrecondition.
        XCTAssertTrue(Thread.isMainThread, "Precondition: test deve girare sul main thread")

        let service = ManagedPostgresService()
        // bootstrapIfNeeded può fallire (Postgres non disponibile), ma non deve crashare.
        _ = try? service.bootstrapIfNeeded()
        // Se arriviamo qui, nessun crash è avvenuto.
    }

    func testPersistenceStoreIfAvailableDoesNotCrashOnMainThread() {
        // persistenceStoreIfAvailable() è il punto d'ingresso più comune
        // che indirettamente chiama bootstrapIfNeeded(). Non deve crashare.
        XCTAssertTrue(Thread.isMainThread)
        _ = MCPSharedState.persistenceStoreIfAvailable()
    }

    // MARK: - Background thread behavior preserved

    func testBootstrapIfNeededWorksOnBackgroundThread() {
        let expectation = expectation(description: "background bootstrap")

        DispatchQueue.global(qos: .utility).async {
            let service = ManagedPostgresService()
            _ = try? service.bootstrapIfNeeded()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }
}
