import XCTest
@testable import CoderIDE

@MainActor
final class UIPanelCoordinatorTests: XCTestCase {
    func testDefaultState() {
        let coordinator = UIPanelCoordinator()

        XCTAssertFalse(coordinator.showTerminal)
        XCTAssertEqual(coordinator.terminalHeight, 200)
        XCTAssertFalse(coordinator.showSettings)
        XCTAssertFalse(coordinator.showPlanPanel)
        XCTAssertFalse(coordinator.showDebugPanel)
        XCTAssertFalse(coordinator.showSwarmPanel)
        XCTAssertFalse(coordinator.showCodeReviewPanel)
        XCTAssertFalse(coordinator.showBrowserPanel)
        XCTAssertTrue(coordinator.showChatPanel)
        XCTAssertNil(coordinator.selectedConversationId)
        XCTAssertEqual(coordinator.coderMode, .agent)
        XCTAssertTrue(coordinator.preferActiveContextForGlobalThread)
        XCTAssertFalse(coordinator.showAppUpdateAlert)
        XCTAssertNil(coordinator.pendingAppUpdate)
        XCTAssertFalse(coordinator.isSelectingProjectFolders)
        XCTAssertFalse(coordinator.isSelectingAddFolder)
        XCTAssertNil(coordinator.pendingAddFolderContextId)
        XCTAssertEqual(coordinator.pendingFolderPickerKind, .none)
        XCTAssertFalse(coordinator.showFolderPicker)
    }

    func testPanelVisibilityToggle() {
        let coordinator = UIPanelCoordinator()

        coordinator.showTerminal = true
        XCTAssertTrue(coordinator.showTerminal)

        coordinator.showTerminal = false
        XCTAssertFalse(coordinator.showTerminal)
    }

    func testConversationSelection() {
        let coordinator = UIPanelCoordinator()
        let id = UUID()

        coordinator.selectedConversationId = id
        XCTAssertEqual(coordinator.selectedConversationId, id)

        coordinator.selectedConversationId = nil
        XCTAssertNil(coordinator.selectedConversationId)
    }

    func testCoderModeChange() {
        let coordinator = UIPanelCoordinator()

        coordinator.coderMode = .ide
        XCTAssertEqual(coordinator.coderMode, .ide)

        coordinator.coderMode = .browser
        XCTAssertEqual(coordinator.coderMode, .browser)

        coordinator.coderMode = .agent
        XCTAssertEqual(coordinator.coderMode, .agent)
    }

    func testFolderPickerKind() {
        let coordinator = UIPanelCoordinator()
        let contextId = UUID()

        coordinator.pendingFolderPickerKind = .openProject
        XCTAssertEqual(coordinator.pendingFolderPickerKind, .openProject)

        coordinator.pendingFolderPickerKind = .addFolderToContext(contextId)
        if case .addFolderToContext(let id) = coordinator.pendingFolderPickerKind {
            XCTAssertEqual(id, contextId)
        } else {
            XCTFail("Expected .addFolderToContext")
        }

        coordinator.pendingFolderPickerKind = .none
        XCTAssertEqual(coordinator.pendingFolderPickerKind, .none)
    }
}
