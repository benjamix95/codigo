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

    func testPromptBuilderReviewerIncludesMandatoryMCPTools() {
        let prompt = SubagentPromptBuilder.build(role: .reviewer, task: "review this")
        let requiredTools = [
            "coderide_review_start",
            "coderide_bughunter_start",
            "coderide_security_start",
            "coderide_diagnostics",
            "coderide_read_lints",
            "coderide_review_status",
            "coderide_review_findings",
            "coderide_bughunter_findings",
            "coderide_security_findings",
            "coderide_review_diff_summary",
            "coderide_audit_bug_nil_crash_paths",
            "coderide_audit_bug_error_handling",
            "coderide_audit_bug_concurrency",
            "coderide_audit_bug_api_contracts",
            "coderide_audit_bug_test_gaps",
            "coderide_audit_security_secrets",
            "coderide_audit_security_patterns",
            "coderide_audit_correlate_findings",
        ]
        for tool in requiredTools {
            XCTAssertTrue(
                prompt.contains(tool),
                "Reviewer prompt MUST reference MCP tool: \(tool)"
            )
        }
        XCTAssertTrue(prompt.contains("MANDATORY"))
        XCTAssertTrue(prompt.contains("Text-only"))
    }

    func testPromptBuilderTestWriterIncludesRunAndFixLoopInstructions() {
        let prompt = SubagentPromptBuilder.build(role: .testWriter, task: "add tests")
        XCTAssertTrue(prompt.contains("Read ALL existing test files"))
        XCTAssertTrue(prompt.contains("full test suite"))
        XCTAssertTrue(prompt.contains("If tests fail, fix them and re-run"))
    }

    func testPromptBuilderTestWriterIncludesMandatoryMCPTools() {
        let prompt = SubagentPromptBuilder.build(role: .testWriter, task: "add tests")
        let requiredTools = [
            "coderide_diagnostics",
            "coderide_read_lints",
            "coderide_audit_bug_test_gaps",
            "coderide_audit_bug_test_impact",
        ]
        for tool in requiredTools {
            XCTAssertTrue(
                prompt.contains(tool),
                "TestWriter prompt MUST reference MCP tool: \(tool)"
            )
        }
        XCTAssertTrue(prompt.contains("MANDATORY"))
        XCTAssertTrue(prompt.contains("execution is mandatory"))
    }

    func testPromptBuilderDocWriterIncludesMandatoryMCPTools() {
        let prompt = SubagentPromptBuilder.build(role: .docWriter, task: "document changes")
        let requiredTools = [
            "coderide_review_findings",
            "coderide_bughunter_findings",
            "coderide_security_findings",
            "coderide_review_diff_summary",
            "coderide_diagnostics",
            "coderide_read_lints",
            "coderide_read",
            "coderide_file_outline",
            "coderide_write",
            "coderide_create_file",
        ]
        for tool in requiredTools {
            XCTAssertTrue(
                prompt.contains(tool),
                "DocWriter prompt MUST reference MCP tool: \(tool)"
            )
        }
        XCTAssertTrue(prompt.contains("MANDATORY"))
        XCTAssertTrue(prompt.contains("Text-only"))
    }

    func testPromptBuilderDocWriterIncludesStructuredOutputRequirement() {
        let prompt = SubagentPromptBuilder.build(role: .docWriter, task: "document changes")
        XCTAssertTrue(prompt.contains("\"docs_created\""))
        XCTAssertTrue(prompt.contains("\"findings_documented\""))
        XCTAssertTrue(prompt.contains("\"bugs_documented\""))
        XCTAssertTrue(prompt.contains("\"tools_used\""))
    }

    func testPromptBuilderDocWriterPolicyIsNotReadOnly() {
        let prompt = SubagentPromptBuilder.build(role: .docWriter, task: "document changes")
        XCTAssertTrue(prompt.contains("DocWriter policy"))
        XCTAssertFalse(
            prompt.contains("READ-ONLY subagent"),
            "DocWriter MUST NOT have READ-ONLY policy — it needs to write documentation files"
        )
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
            for: .bugHunter,
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
