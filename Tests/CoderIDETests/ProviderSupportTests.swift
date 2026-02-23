import XCTest
import CoderEngine
@testable import CoderIDE

final class ProviderSupportTests: XCTestCase {
    func testUserSelectableRealProvidersContainOnlyCliAndApiProviders() {
        XCTAssertTrue(ProviderSupport.isUserSelectableRealProvider(id: "codex-cli"))
        XCTAssertTrue(ProviderSupport.isUserSelectableRealProvider(id: "claude-cli"))
        XCTAssertTrue(ProviderSupport.isUserSelectableRealProvider(id: "gemini-cli"))
        XCTAssertTrue(ProviderSupport.isUserSelectableRealProvider(id: "openrouter-api"))
        XCTAssertTrue(ProviderSupport.isUserSelectableRealProvider(id: "openai-api"))

        XCTAssertFalse(ProviderSupport.isUserSelectableRealProvider(id: "not-a-provider"))
        XCTAssertFalse(ProviderSupport.isUserSelectableRealProvider(id: "internal-test-provider"))
        XCTAssertFalse(ProviderSupport.isUserSelectableRealProvider(id: "legacy-provider-id"))
    }

    func testPlanBuildExecutionCapabilityAllowsCliAndApiProviders() {
        let registry = ProviderRegistry()
        registry.register(MockTestProvider(id: "codex-cli", authenticated: true))
        registry.register(MockTestProvider(id: "openai-api", authenticated: true))

        XCTAssertTrue(
            ProviderSupport.isPlanBuildExecutionCapableProvider(id: "codex-cli", registry: registry)
        )
        XCTAssertTrue(
            ProviderSupport.isPlanBuildExecutionCapableProvider(id: "openai-api", registry: registry)
        )
    }

    func testPlanBuildExecutionCapabilityRequiresProviderRegistration() {
        let registry = ProviderRegistry()
        XCTAssertFalse(
            ProviderSupport.isPlanBuildExecutionCapableProvider(id: "claude-cli", registry: registry)
        )
    }
}

private struct MockTestProvider: LLMProvider {
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
