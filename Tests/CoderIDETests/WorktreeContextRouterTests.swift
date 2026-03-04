import XCTest
@testable import CoderIDE

@MainActor
final class WorktreeContextRouterTests: XCTestCase {
    private var tempDirURL: URL!
    private var chatDefaults: UserDefaults!
    private var chatSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-router-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)

        chatSuiteName = "worktree-router-chat-\(UUID().uuidString)"
        chatDefaults = UserDefaults(suiteName: chatSuiteName)
        chatDefaults.removePersistentDomain(forName: chatSuiteName)

        clearContextPersistence()
    }

    override func tearDownWithError() throws {
        if let tempDirURL {
            try? FileManager.default.removeItem(at: tempDirURL)
        }
        if let chatSuiteName {
            chatDefaults?.removePersistentDomain(forName: chatSuiteName)
        }
        clearContextPersistence()
        tempDirURL = nil
        chatDefaults = nil
        chatSuiteName = nil
        try super.tearDownWithError()
    }

    func testSwitchConversationCreatesProjectContextAndAssignsConversation() throws {
        let chatStore = ChatStore(userDefaults: chatDefaults)
        let conversationId = chatStore.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        let projectContextStore = ProjectContextStore()
        let workspaceStore = WorkspaceStore()

        try WorktreeContextRouter.switchConversation(
            conversationId: conversationId,
            toProjectPath: tempDirURL.path,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            workspaceStore: workspaceStore
        )

        let conv = try XCTUnwrap(chatStore.conversation(for: conversationId))
        let contextId = try XCTUnwrap(conv.contextId)
        let context = try XCTUnwrap(projectContextStore.context(id: contextId))
        XCTAssertEqual(context.folderPaths, [tempDirURL.path])
        XCTAssertEqual(projectContextStore.activeContextId, contextId)
        XCTAssertEqual(workspaceStore.activeWorkspaceId, contextId)
        XCTAssertEqual(workspaceStore.workspaces.first(where: { $0.id == contextId })?.folderPaths, [tempDirURL.path])
    }

    private func clearContextPersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.projectContexts")
        defaults.removeObject(forKey: "CoderIDE.activeContextId")
        defaults.removeObject(forKey: "CoderIDE.lastActiveConversationByContext")
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
    }
}
