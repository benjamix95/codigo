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
            fastMode: true,
            preferOpenAIResponsesWireAPI: false
        )

        XCTAssertTrue(args.contains("fast_mode=true"))
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
            fastMode: true,
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
            fastMode: false,
            preferOpenAIResponsesWireAPI: true
        )

        XCTAssertTrue(args.contains("fast_mode=false"))
        XCTAssertFalse(args.contains("model_providers.openai.name=\"openai\""))
        XCTAssertFalse(args.contains("model_providers.openai.wire_api=\"responses\""))
    }

    func testRepairedCodexConfigContentReEnablesDisabledCoderIDEMCPServer() {
        let original = """
        model = "gpt-5.4"

        [mcp_servers.coderide]
        command = "/tmp/coderide-mcp-server"
        args = [ "--workspace", "." ]
        enabled = false
        """

        let repaired = CodexCLIProvider.repairedCodexConfigContentIfNeeded(original)

        XCTAssertTrue(repaired.contains("enabled = true"))
        XCTAssertFalse(repaired.contains("enabled = false"))
    }
}
