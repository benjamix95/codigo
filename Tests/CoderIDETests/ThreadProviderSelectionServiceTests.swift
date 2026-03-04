import XCTest
import CoderEngine
@testable import CoderIDE

final class ThreadProviderSelectionServiceTests: XCTestCase {
    func testModeNilWithPreferredProviderRestoresPreferred() {
        let registry = ProviderRegistry()
        registry.register(ThreadProviderMockProvider(id: "codex-cli", authenticated: true))
        registry.register(ThreadProviderMockProvider(id: "claude-cli", authenticated: true))
        let conversation = Conversation(mode: nil, preferredProviderId: "claude-cli")

        let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conversation,
            currentProviderId: "codex-cli",
            registry: registry
        )

        XCTAssertEqual(resolved, "claude-cli")
    }

    func testMissingPreferredProviderRemainsBoundWithoutFallback() {
        let registry = ProviderRegistry()
        registry.register(ThreadProviderMockProvider(id: "codex-cli", authenticated: true))
        let conversation = Conversation(mode: nil, preferredProviderId: "openrouter-api")

        let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conversation,
            currentProviderId: "codex-cli",
            registry: registry
        )

        XCTAssertEqual(resolved, "openrouter-api")
    }

    func testIDEModeKeepsPreferredProviderEvenWhenAnotherIsAuthenticated() {
        let registry = ProviderRegistry()
        registry.register(ThreadProviderMockProvider(id: "openai-api", authenticated: false))
        registry.register(ThreadProviderMockProvider(id: "anthropic-api", authenticated: true))
        let conversation = Conversation(mode: .ide, preferredProviderId: "openai-api")

        let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conversation,
            currentProviderId: "anthropic-api",
            registry: registry
        )

        XCTAssertEqual(resolved, "openai-api")
    }

    func testNoPreferredProviderFallsBackToDefaultProvider() {
        let registry = ProviderRegistry()
        registry.register(ThreadProviderMockProvider(id: "codex-cli", authenticated: false))
        registry.register(ThreadProviderMockProvider(id: "openai-api", authenticated: true))
        let conversation = Conversation(mode: nil, preferredProviderId: nil)

        let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conversation,
            currentProviderId: nil,
            registry: registry
        )

        XCTAssertEqual(resolved, "openai-api")
    }
}

@MainActor
final class ThreadProviderSelectionPersistenceTests: XCTestCase {
    private let conversationsStorageKey = "CoderIDE.conversations"
    private let planBoardsStorageKey = "CoderIDE.planBoards"
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ThreadProviderSelectionPersistenceTests.\(UUID().uuidString)"
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

    func testPersistRuntimeProviderSelectionUpdatesConversationPreferredProvider() throws {
        let store = ChatStore(userDefaults: isolatedDefaults)
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        ThreadProviderSelectionService.persistRuntimeProviderSelection(
            chatStore: store,
            conversationId: conversationId,
            runtimeProviderId: "claude-cli"
        )

        XCTAssertEqual(
            store.conversation(for: conversationId)?.preferredProviderId,
            "claude-cli"
        )
    }

    private func clearPersistedState() {
        isolatedDefaults.removeObject(forKey: conversationsStorageKey)
        isolatedDefaults.removeObject(forKey: planBoardsStorageKey)
    }
}

private struct ThreadProviderMockProvider: LLMProvider {
    let id: String
    let displayName: String
    let authenticated: Bool

    init(id: String, authenticated: Bool) {
        self.id = id
        self.displayName = id
        self.authenticated = authenticated
    }

    func isAuthenticated() -> Bool { authenticated }

    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
