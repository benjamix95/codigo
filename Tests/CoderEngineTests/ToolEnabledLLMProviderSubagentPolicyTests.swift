import XCTest
@testable import CoderEngine

final class ToolEnabledLLMProviderSubagentPolicyTests: XCTestCase {
    func testToolProtocolPromptPrefersSoloCodeSubagentToolsOverProviderForking() {
        let provider = ToolEnabledLLMProvider(
            base: StubPromptOnlyProvider(),
            runtime: UnifiedToolRuntime(executionController: nil, executionScope: .agent),
            policy: ToolRuntimePolicy(),
            executionScope: .agent,
            executionController: nil,
            subagentProviderFactory: { StubPromptOnlyProvider() }
        )

        let prompt = provider.toolProtocolPrompt

        XCTAssertTrue(prompt.contains("Use the native `subagent_*` tools for delegation"))
        XCTAssertTrue(prompt.contains("Do not switch to provider-native fork/collaboration APIs"))
        XCTAssertTrue(prompt.contains("fall back silently to `subagent_*` or direct tools"))
    }
}

private struct StubPromptOnlyProvider: LLMProvider {
    let id = "stub-prompt-only"
    let displayName = "Stub Prompt Only"
    let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: false,
        nativeDocument: false,
        nativeFile: false
    )

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
