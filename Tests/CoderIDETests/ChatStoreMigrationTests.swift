import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ChatStoreMigrationTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let ctxKey = "CoderIDE.projectContexts"

    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    func testMigratesLegacyWorkspaceIdToContextId() throws {
        let wsId = UUID()
        let legacy = Conversation(title: "legacy", messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: wsId, adHocFolderPaths: [])
        let data = try JSONEncoder().encode([legacy])
        UserDefaults.standard.set(data, forKey: convKey)

        let workspaceStore = WorkspaceStore()
        workspaceStore.workspaces = [Workspace(id: wsId, name: "WS", folderPaths: ["/tmp"], excludedPaths: [])]
        let contextStore = ProjectContextStore()
        let chatStore = ChatStore()

        chatStore.migrateLegacyContextsIfNeeded(contextStore: contextStore, workspaceStore: workspaceStore)

        XCTAssertEqual(chatStore.conversations.first?.contextId, wsId)
    }

    func testMigratesLegacyAdHocPathsToSingleProjectContext() throws {
        let folder = "/tmp/my-folder-\(UUID().uuidString)"
        let legacy = Conversation(title: "legacy", messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: nil, adHocFolderPaths: [folder])
        let data = try JSONEncoder().encode([legacy])
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

    func testLegacyConversationWithoutPreferredProviderIdDecodesAsNil() throws {
        // JSON senza preferredProviderId (dati vecchi) deve decodificare con preferredProviderId == nil
        let legacyJson = """
        [{"id":"\(UUID().uuidString)","title":"old","messages":[],"createdAt":"2020-01-01T00:00:00.000Z","contextId":null,"contextFolderPath":null,"mode":"Agent","isArchived":false,"isPinned":false,"isFavorite":false,"workspaceId":null,"adHocFolderPaths":[],"checkpoints":[]}]
        """
        let data = try XCTUnwrap(legacyJson.data(using: .utf8))
        UserDefaults.standard.set(data, forKey: convKey)

        let chatStore = ChatStore()
        let conv = chatStore.conversations.first
        XCTAssertNotNil(conv)
        XCTAssertNil(conv?.preferredProviderId)
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: ctxKey)
    }
}
