import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ChatStoreMigrationTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let ctxKey = "CoderIDE.projectContexts"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: ctxKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: ctxKey)
    }

    func testMigratesLegacyWorkspaceIdToContextId() {
        let wsId = UUID()
        let legacy = Conversation(title: "legacy", messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: wsId, adHocFolderPaths: [])
        let data = try! JSONEncoder().encode([legacy])
        UserDefaults.standard.set(data, forKey: convKey)

        let workspaceStore = WorkspaceStore()
        workspaceStore.workspaces = [Workspace(id: wsId, name: "WS", folderPaths: ["/tmp"], excludedPaths: [])]
        let contextStore = ProjectContextStore()
        let chatStore = ChatStore()

        chatStore.migrateLegacyContextsIfNeeded(contextStore: contextStore, workspaceStore: workspaceStore)

        XCTAssertEqual(chatStore.conversations.first?.contextId, wsId)
    }

    func testMigratesLegacyAdHocPathsToSingleProjectContext() {
        let folder = "/tmp/my-folder-\(UUID().uuidString)"
        let legacy = Conversation(title: "legacy", messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: nil, adHocFolderPaths: [folder])
        let data = try! JSONEncoder().encode([legacy])
        UserDefaults.standard.set(data, forKey: convKey)

        let workspaceStore = WorkspaceStore()
        let contextStore = ProjectContextStore()
        let chatStore = ChatStore()

        chatStore.migrateLegacyContextsIfNeeded(contextStore: contextStore, workspaceStore: workspaceStore)

        let migrated = chatStore.conversations.first
        XCTAssertNotNil(migrated?.contextId)
        let context = contextStore.context(id: migrated?.contextId)
        XCTAssertEqual(context?.kind, .singleProject)
        XCTAssertEqual(context?.folderPaths, [folder])
    }
}
