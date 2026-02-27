import XCTest
@testable import CoderEngine

final class CodexCLIProviderInvocationTests: XCTestCase {
    func testStreamInvocationUsesDirectCodexProcessWithoutPTYWrapper() {
        let invocation = CodexCLIProvider.streamInvocation(
            executable: "/usr/local/bin/codex",
            arguments: ["exec", "--json", "prompt"]
        )

        XCTAssertEqual(invocation.executable, "/usr/local/bin/codex")
        XCTAssertEqual(invocation.arguments, ["exec", "--json", "prompt"])
    }

    func testBuildExecArgumentsDoesNotInjectResponsesWireAPIByDefault() {
        let args = CodexCLIProvider.buildExecArguments(
            fullPrompt: "prompt",
            imageURLs: nil,
            sandboxMode: .workspaceWrite,
            yoloMode: false,
            askForApproval: "never",
            workspacePath: "/tmp",
            modelOverride: nil,
            modelReasoningEffort: nil,
            modelProviderOverride: nil,
            preferOpenAIResponsesWireAPI: false
        )

        XCTAssertFalse(args.contains("model_providers.openai.name=\"openai\""))
        XCTAssertFalse(args.contains("model_providers.openai.wire_api=\"responses\""))
    }

    func testBuildExecArgumentsInjectsResponsesWireAPIWhenEnabledForOpenAI() {
        let args = CodexCLIProvider.buildExecArguments(
            fullPrompt: "prompt",
            imageURLs: nil,
            sandboxMode: .workspaceWrite,
            yoloMode: false,
            askForApproval: "never",
            workspacePath: "/tmp",
            modelOverride: nil,
            modelReasoningEffort: nil,
            modelProviderOverride: "openai",
            preferOpenAIResponsesWireAPI: true
        )

        XCTAssertTrue(args.contains("model_providers.openai.name=\"openai\""))
        XCTAssertTrue(args.contains("model_providers.openai.wire_api=\"responses\""))
    }

    func testBuildExecArgumentsDoesNotInjectResponsesWireAPIForNonOpenAIProvider() {
        let args = CodexCLIProvider.buildExecArguments(
            fullPrompt: "prompt",
            imageURLs: nil,
            sandboxMode: .workspaceWrite,
            yoloMode: false,
            askForApproval: "never",
            workspacePath: "/tmp",
            modelOverride: nil,
            modelReasoningEffort: nil,
            modelProviderOverride: "azure",
            preferOpenAIResponsesWireAPI: true
        )

        XCTAssertFalse(args.contains("model_providers.openai.name=\"openai\""))
        XCTAssertFalse(args.contains("model_providers.openai.wire_api=\"responses\""))
    }
}
