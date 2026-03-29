import XCTest
@testable import CoderIDE
@testable import CoderEngine

// MARK: - Warm-Start Polling Regression Tests
//
// Verifica che il polling dell'indice non sovrascriva il badge warm-start
// (.ready) con uno stato .idle quando l'attore non ha ancora iniziato.

@MainActor
final class WorkspaceStoreWarmStartPollingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
        defaults.removeObject(forKey: "codebase_index_enabled")
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
        defaults.removeObject(forKey: "codebase_index_enabled")
        super.tearDown()
    }

    // MARK: - Test 1: polling .idle non sovrascrive warm-start .ready

    func testApplyIndexStatusDoesNotDowngradeReadyToIdle() {
        let store = WorkspaceStore()

        // Simula warm-start: badge impostato a .ready
        store.indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: .ready,
            hasWorkspacePaths: true,
            indexingEnabled: true
        )

        // Simula primo poll: l'attore è ancora .idle (indexWorkspace non è partito)
        let idleInfo = IndexStatusInfo(
            status: .idle,
            totalFiles: 0,
            totalSourceFiles: 0,
            totalSymbols: 0,
            lastIndexedAt: nil,
            indexDurationMs: 0,
            workspacePaths: [],
            progress: nil
        )
        store.applyIndexStatus(idleInfo)

        // Il badge deve restare .ready, NON tornare a .idle (che mostrerebbe 0%)
        XCTAssertEqual(
            store.indexBadgeState.status, .ready,
            "Il polling .idle non deve sovrascrivere il badge warm-start .ready"
        )
        XCTAssertEqual(
            store.indexBadgeState.displayPercent, 100,
            "displayPercent deve restare 100 dopo polling .idle su warm-start"
        )
    }

    // MARK: - Test 2: polling .indexing con progress aggiorna correttamente

    func testApplyIndexStatusAllowsIndexingToOverrideReady() {
        let store = WorkspaceStore()

        store.indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: .ready,
            hasWorkspacePaths: true,
            indexingEnabled: true
        )

        // L'attore ha iniziato indexWorkspace: status .indexing con progress
        let indexingInfo = IndexStatusInfo(
            status: .indexing,
            totalFiles: 10,
            totalSourceFiles: 8,
            totalSymbols: 0,
            lastIndexedAt: nil,
            indexDurationMs: 0,
            workspacePaths: [],
            progress: IndexingProgress(current: 6200, total: 10000)
        )
        store.applyIndexStatus(indexingInfo)

        // Il badge deve aggiornarsi a .indexing — il warm-start non blocca stati validi
        XCTAssertEqual(
            store.indexBadgeState.status, .indexing,
            "Lo stato .indexing con progress deve aggiornare il badge normalmente"
        )
        XCTAssertEqual(
            store.indexBadgeState.displayPercent, 62,
            "displayPercent deve riflettere il progress reale"
        )
    }

    // MARK: - Test 3: da .idle a .idle non viene bloccato (nessun warm-start attivo)

    func testApplyIndexStatusAllowsIdleWhenNotWarmStarted() {
        let store = WorkspaceStore()

        // Badge iniziale: .idle (nessun warm-start)
        store.indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: .idle,
            hasWorkspacePaths: true,
            indexingEnabled: true
        )

        let idleInfo = IndexStatusInfo(
            status: .idle,
            totalFiles: 0,
            totalSourceFiles: 0,
            totalSymbols: 0,
            lastIndexedAt: nil,
            indexDurationMs: 0,
            workspacePaths: [],
            progress: nil
        )
        store.applyIndexStatus(idleInfo)

        // .idle → .idle è ok (nessun warm-start da proteggere)
        XCTAssertEqual(store.indexBadgeState.status, .idle)
        XCTAssertEqual(store.indexBadgeState.displayPercent, 0)
    }

    // MARK: - Test 4: .ready completato (post-indexing) accetta .idle per reset

    func testApplyIndexStatusAllowsIdleWithProgressToOverrideReady() {
        let store = WorkspaceStore()

        store.indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: .ready,
            hasWorkspacePaths: true,
            indexingEnabled: true
        )

        // .idle con progress non-nil (scenario edge) → deve aggiornare
        let idleWithProgress = IndexStatusInfo(
            status: .idle,
            totalFiles: 5,
            totalSourceFiles: 3,
            totalSymbols: 10,
            lastIndexedAt: Date(),
            indexDurationMs: 100,
            workspacePaths: [],
            progress: IndexingProgress(current: 0, total: 100)
        )
        store.applyIndexStatus(idleWithProgress)

        // Con progress non-nil il guard non si attiva — aggiornamento normale
        XCTAssertEqual(store.indexBadgeState.status, .idle)
    }
}
