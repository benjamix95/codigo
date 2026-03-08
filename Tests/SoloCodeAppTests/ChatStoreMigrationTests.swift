import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ChatStoreMigrationTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let ctxKey = "CoderIDE.projectContexts"
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ChatStoreMigrationTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMigratesLegacyWorkspaceIdToContextId() throws {
        let wsId = UUID()
        let title = "legacy-\(UUID().uuidString)"
        let legacy = Conversation(title: title, messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: wsId, adHocFolderPaths: [])
        let data = try JSONEncoder().encode([legacy])
        isolatedDefaults.set(data, forKey: convKey)

        let workspaceStore = WorkspaceStore()
        workspaceStore.workspaces = [Workspace(id: wsId, name: "WS", folderPaths: ["/tmp"], excludedPaths: [])]
        let contextStore = ProjectContextStore()
        let chatStore = ChatStore(userDefaults: isolatedDefaults)

        chatStore.migrateLegacyContextsIfNeeded(contextStore: contextStore, workspaceStore: workspaceStore)

        let migrated = chatStore.conversations.first(where: { $0.title == title })
        XCTAssertNotNil(migrated)
        XCTAssertEqual(migrated?.contextId, wsId)
    }

    func testMigratesLegacyAdHocPathsToSingleProjectContext() throws {
        let folder = "/tmp/my-folder-\(UUID().uuidString)"
        let title = "legacy-\(UUID().uuidString)"
        let legacy = Conversation(title: title, messages: [], createdAt: .now, contextId: nil, mode: .agent, workspaceId: nil, adHocFolderPaths: [folder])
        let data = try JSONEncoder().encode([legacy])
        isolatedDefaults.set(data, forKey: convKey)

        let workspaceStore = WorkspaceStore()
        let contextStore = ProjectContextStore()
        let chatStore = ChatStore(userDefaults: isolatedDefaults)

        chatStore.migrateLegacyContextsIfNeeded(contextStore: contextStore, workspaceStore: workspaceStore)

        let migrated = chatStore.conversations.first(where: { $0.title == title })
        XCTAssertNotNil(migrated?.contextId)
        let context = contextStore.context(id: migrated?.contextId)
        XCTAssertEqual(context?.kind, .singleProject)
        XCTAssertEqual(context?.folderPaths, [folder])
    }

    func testLegacyConversationWithoutPreferredProviderIdDecodesAsNil() throws {
        // JSON senza preferredProviderId (dati vecchi) deve decodificare con preferredProviderId == nil
        let legacyId = UUID()
        let legacyJson = """
        [{"id":"\(legacyId.uuidString)","title":"old","messages":[],"createdAt":0,"contextId":null,"contextFolderPath":null,"mode":"Agent","isArchived":false,"isPinned":false,"isFavorite":false,"workspaceId":null,"adHocFolderPaths":[],"checkpoints":[]}]
        """
        let data = try XCTUnwrap(legacyJson.data(using: .utf8))
        let decoded = try JSONDecoder().decode([Conversation].self, from: data)
        let conv = decoded.first(where: { $0.id == legacyId })
        XCTAssertNotNil(conv)
        XCTAssertNil(conv?.preferredProviderId)
    }

    private func clearPersistedState() {
        isolatedDefaults.removeObject(forKey: convKey)
        isolatedDefaults.removeObject(forKey: ctxKey)
    }
}
