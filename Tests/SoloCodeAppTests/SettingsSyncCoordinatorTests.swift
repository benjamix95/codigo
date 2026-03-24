import XCTest
@testable import CoderEngine
@testable import CoderIDE

@MainActor
final class SettingsSyncCoordinatorTests: XCTestCase {
    func testBindSetsWeakReferences() {
        let coordinator = SettingsSyncCoordinator()
        let registry = CoderEngine.ProviderRegistry()
        let execution = CoderEngine.ExecutionController()
        let workspace = WorkspaceStore()

        coordinator.bind(registry: registry, execution: execution, workspace: workspace)

        XCTAssertNotNil(coordinator.providerRegistry)
        XCTAssertNotNil(coordinator.executionController)
        XCTAssertNotNil(coordinator.workspaceStore)
    }

    func testSyncAllDoesNotCrashWithNilDependencies() {
        let coordinator = SettingsSyncCoordinator()
        // No bind() called — all weak refs are nil
        // Should not crash
        coordinator.syncAll()
    }

    func testSyncIndividualProvidersDoNotCrashWithNilDependencies() {
        let coordinator = SettingsSyncCoordinator()

        coordinator.syncOpenAI()
        coordinator.syncAnthropic()
        coordinator.syncGoogle()
        coordinator.syncMiniMax()
        coordinator.syncOpenRouter()
        coordinator.syncGrok()
        coordinator.syncCodex()
        coordinator.syncClaude()
        coordinator.syncGemini()
        coordinator.syncKilo()
        coordinator.syncPlanProvider()
        coordinator.syncSwarm()
        coordinator.syncCodeReview()
    }
}
