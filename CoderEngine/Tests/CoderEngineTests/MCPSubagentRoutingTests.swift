import XCTest
@testable import CoderEngine

final class MCPSubagentRoutingTests: XCTestCase {

    func testExecutionIdentityUsesTaskDerivedAgentName() {
        let identity = SubagentExecutionIdentityBuilder.make(
            role: .explorer,
            task: "Investigate the auth token refresh flow and session invalidation"
        )

        XCTAssertEqual(identity.agentName, "Explorer-AuthTokenRefreshFlowSessionInvalidation")
        XCTAssertEqual(identity.swarmId, identity.agentName)
        XCTAssertTrue(identity.taskSummary.contains("auth token refresh flow"))
    }

    func testExecutionIdentityStripsItalianFillerWordsFromExplorerName() {
        let identity = SubagentExecutionIdentityBuilder.make(
            role: .explorer,
            task: "Rivedi la pipeline del debug mode lato UI orchestrazione e intent dispatch"
        )

        XCTAssertEqual(identity.agentName, "Explorer-PipelineDebugModeUIOrchestrazioneIntentDispatch")
    }

    func testPromptBuilderProducesNonEmptyForAllRoles() {
        for role in SubagentRole.allCases {
            let prompt = SubagentPromptBuilder.build(role: role, task: "test task")
            XCTAssertFalse(prompt.isEmpty, "Prompt for \(role) should not be empty")
            XCTAssertTrue(prompt.contains("test task"), "Prompt for \(role) should contain the task")
        }
    }

    func testPromptBuilderReviewerIncludesStructuredSummaryInstruction() {
        let prompt = SubagentPromptBuilder.build(role: .reviewer, task: "review this")
        XCTAssertTrue(prompt.contains("do NOT auto-fix"))
        XCTAssertTrue(prompt.contains("\"issues_found\""))
        XCTAssertTrue(prompt.contains("\"critical\""))
        XCTAssertTrue(prompt.contains("\"warnings\""))
        XCTAssertTrue(prompt.contains("\"suggestions\""))
    }

    func testPromptBuilderTestWriterIncludesRunAndFixLoopInstructions() {
        let prompt = SubagentPromptBuilder.build(role: .testWriter, task: "add tests")
        XCTAssertTrue(prompt.contains("ALWAYS read existing test files first"))
        XCTAssertTrue(prompt.contains("run the relevant test command"))
        XCTAssertTrue(prompt.contains("If tests fail, fix and re-run"))
    }

    func testBackendResolverPrefersCodexForReadOnlyRole() {
        let selection = SubagentBackendResolver.selectBackend(
            for: .explorer,
            discoveredCLIs: [
                "claude": "/usr/local/bin/claude",
                "codex": "/usr/local/bin/codex",
            ]
        )

        XCTAssertEqual(selection?.providerID, "codex")
        XCTAssertEqual(selection?.cliPath, "/usr/local/bin/codex")
    }

    func testBackendResolverFallsBackToClaudeForReadOnlyRole() {
        let selection = SubagentBackendResolver.selectBackend(
            for: .reviewer,
            discoveredCLIs: [
                "claude": "/usr/local/bin/claude",
            ]
        )

        XCTAssertEqual(selection?.providerID, "claude")
        XCTAssertEqual(selection?.cliPath, "/usr/local/bin/claude")
    }

    func testBackendResolverRejectsReadOnlyOnlyBackendsForWriteRole() {
        let selection = SubagentBackendResolver.selectBackend(
            for: .coder,
            discoveredCLIs: [
                "claude": "/usr/local/bin/claude",
            ]
        )

        XCTAssertNil(selection)
    }

    func testAsyncBackendResolverSkipsProvidersMarkedUnhealthy() async {
        await SubagentProviderHealthRuntime.shared.resetForTests()
        defer {
            Task {
                await SubagentProviderHealthRuntime.shared.resetForTests()
            }
        }

        await SubagentProviderHealthRuntime.shared.overrideHealthStatusForTests(
            providerID: "codex",
            status: .unhealthy
        )

        let selection = await SubagentBackendResolver.selectBackend(
            for: .explorer,
            discoveredCLIs: [
                "claude": "/usr/local/bin/claude",
                "codex": "/usr/local/bin/codex",
            ]
        )

        XCTAssertEqual(selection?.providerID, "claude")
    }
}
