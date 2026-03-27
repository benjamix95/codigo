import XCTest
@testable import CoderEngine

final class MCPSubagentPipelineTests: XCTestCase {

    // MARK: - buildCLIArgs — Codex

    func testBuildCLIArgs_codex_readOnly() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/codex",
            prompt: "Investigate auth flow",
            workspacePath: "/tmp/project",
            readOnly: true
        )
        XCTAssertEqual(args, [
            "exec", "--full-auto", "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--cd", "/tmp/project",
            "Investigate auth flow",
        ])
    }

    func testBuildCLIArgs_codex_readWrite() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/opt/homebrew/bin/codex",
            prompt: "Fix the bug",
            workspacePath: "/home/user/repo",
            readOnly: false
        )
        XCTAssertEqual(args, [
            "exec", "--full-auto", "--skip-git-repo-check",
            "--sandbox", "workspace-write",
            "--cd", "/home/user/repo",
            "Fix the bug",
        ])
    }

    func testBuildCLIArgs_codex_noLegacyQFlag() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/codex",
            prompt: "task",
            workspacePath: "/tmp",
            readOnly: false
        )
        XCTAssertFalse(args.contains("-q"), "-q is not a valid codex flag")
        XCTAssertTrue(args.contains("exec"), "codex requires the exec subcommand")
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
    }

    // MARK: - buildCLIArgs — Claude

    func testBuildCLIArgs_claude_readOnly() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/claude",
            prompt: "Review code",
            workspacePath: "/tmp/project",
            readOnly: true
        )
        XCTAssertEqual(args, [
            "-p", "Review code",
            "--output-format", "text",
            "--allowedTools", "Read,Search,Glob,Grep",
        ])
    }

    func testBuildCLIArgs_claude_readWrite() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/opt/homebrew/bin/claude",
            prompt: "Write tests",
            workspacePath: "/tmp/project",
            readOnly: false
        )
        XCTAssertEqual(args, [
            "-p", "Write tests",
            "--output-format", "text",
        ])
    }

    func testBuildCLIArgs_claude_prefersCoderideMCPWhenConfigExists() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/claude",
            prompt: "Review code",
            workspacePath: "/tmp/project",
            readOnly: true,
            claudeMCPConfigPath: "/tmp/claude-mcp-config.json"
        )
        XCTAssertEqual(args, [
            "-p", "Review code",
            "--output-format", "text",
            "--mcp-config", "/tmp/claude-mcp-config.json",
            "--permission-mode", "bypassPermissions",
            "--disallowedTools", "Read,Edit,Write,Glob,Grep,WebSearch,WebFetch,NotebookEdit,TodoWrite",
        ])
    }

    func testMakeClaudeMCPConfigPath_writesWorkspaceScopedConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeServer = root.appendingPathComponent("coderide-mcp-server-rust")
        try Data("stub".utf8).write(to: fakeServer)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: fakeServer.path
        )

        let configPath = try XCTUnwrap(
            SubagentCLIConfig.makeClaudeMCPConfigPath(
                workspacePath: root.path,
                explicitServerPath: fakeServer.path
            )
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])
        let coderide = try XCTUnwrap(servers["coderide"] as? [String: Any])
        let env = try XCTUnwrap(coderide["env"] as? [String: Any])

        XCTAssertEqual(coderide["command"] as? String, fakeServer.path)
        XCTAssertEqual(env["SOLOCODE_WORKSPACE"] as? String, root.path)
    }

    // MARK: - buildCLIArgs — Gemini

    func testBuildCLIArgs_gemini() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/gemini",
            prompt: "Audit security",
            workspacePath: "/tmp/project",
            readOnly: true
        )
        XCTAssertEqual(args, ["-p", "Audit security"])
    }

    // MARK: - buildCLIArgs — Unknown CLI fallback

    func testBuildCLIArgs_unknownCLI() {
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: "/usr/local/bin/mycli",
            prompt: "do something",
            workspacePath: "/tmp",
            readOnly: false
        )
        XCTAssertEqual(args, ["do something"])
    }

    // MARK: - Backend policy / sandbox expectations

    func testPreferredBackendNames_readOnlyIncludesCodexThenClaude() {
        XCTAssertEqual(SubagentCLIConfig.preferredBackendNames(readOnly: true), ["codex", "claude"])
    }

    func testPreferredBackendNames_writeModeRequiresCodex() {
        XCTAssertEqual(SubagentCLIConfig.preferredBackendNames(readOnly: false), ["codex"])
    }

    func testSupportsSandboxExpectations_codexAlwaysTrue() {
        XCTAssertTrue(SubagentCLIConfig.supportsSandboxExpectations(
            cliPath: "/usr/local/bin/codex",
            readOnly: true
        ))
        XCTAssertTrue(SubagentCLIConfig.supportsSandboxExpectations(
            cliPath: "/usr/local/bin/codex",
            readOnly: false
        ))
    }

    func testSupportsSandboxExpectations_claudeOnlyReadOnly() {
        XCTAssertTrue(SubagentCLIConfig.supportsSandboxExpectations(
            cliPath: "/usr/local/bin/claude",
            readOnly: true
        ))
        XCTAssertFalse(SubagentCLIConfig.supportsSandboxExpectations(
            cliPath: "/usr/local/bin/claude",
            readOnly: false
        ))
    }

    func testSupportsSandboxExpectations_geminiRejected() {
        XCTAssertFalse(SubagentCLIConfig.supportsSandboxExpectations(
            cliPath: "/usr/local/bin/gemini",
            readOnly: true
        ))
    }

    // MARK: - isReadOnly

    func testIsReadOnly_explorerIsReadOnly() {
        XCTAssertTrue(SubagentCLIConfig.isReadOnly(.explorer))
    }

    func testIsReadOnly_reviewerIsReadOnly() {
        XCTAssertTrue(SubagentCLIConfig.isReadOnly(.reviewer))
    }

    func testIsReadOnly_bugHunterIsReadOnly() {
        XCTAssertTrue(SubagentCLIConfig.isReadOnly(.bugHunter))
    }

    func testIsReadOnly_securityAuditorIsReadOnly() {
        XCTAssertTrue(SubagentCLIConfig.isReadOnly(.securityAuditor))
    }

    func testIsReadOnly_coderIsNotReadOnly() {
        XCTAssertFalse(SubagentCLIConfig.isReadOnly(.coder))
    }

    func testIsReadOnly_debuggerIsNotReadOnly() {
        XCTAssertFalse(SubagentCLIConfig.isReadOnly(.debugger))
    }

    func testIsReadOnly_testWriterIsNotReadOnly() {
        XCTAssertFalse(SubagentCLIConfig.isReadOnly(.testWriter))
    }

    func testIsReadOnly_docWriterIsNotReadOnly() {
        XCTAssertFalse(SubagentCLIConfig.isReadOnly(.docWriter))
    }

    // MARK: - timeout

    func testTimeout_readOnlyRolesStayUnderMCPDeadline() {
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .explorer), 95)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .reviewer), 95)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .bugHunter), 3600)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .securityAuditor), 95)
    }

    func testTimeout_writeRolesStayUnderMCPDeadline() {
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .coder), 110)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .debugger), 110)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .testWriter), 110)
        XCTAssertEqual(SubagentCLIConfig.timeout(for: .docWriter), 110)
    }

    // MARK: - SubagentRole resolution (all 8 roles)

    func testAllEightRolesResolveFromToolName() {
        let expectations: [(String, SubagentRole)] = [
            ("subagent_explorer", .explorer),
            ("subagent_coder", .coder),
            ("subagent_debugger", .debugger),
            ("subagent_reviewer", .reviewer),
            ("subagent_bugHunter", .bugHunter),
            ("subagent_testWriter", .testWriter),
            ("subagent_docWriter", .docWriter),
            ("subagent_securityAuditor", .securityAuditor),
        ]
        for (toolName, expected) in expectations {
            let resolved = SubagentRole.fromToolName(toolName)
            XCTAssertEqual(resolved, expected, "Expected \(toolName) -> \(expected)")
        }
    }

    func testUnknownRoleReturnsNil() {
        XCTAssertNil(SubagentRole.fromToolName("subagent_plumber"))
        XCTAssertNil(SubagentRole.fromToolName("explorer"))
    }

    func testCoderideAliasResolvesToSubagentRole() {
        XCTAssertEqual(
            SubagentRole.fromToolName("coderide_subagent_explorer"),
            .explorer
        )
        XCTAssertEqual(
            SubagentRole.fromToolName("coderide_subagent_testWriter"),
            .testWriter
        )
    }

    func testNamespacedCoderideAliasResolvesToSubagentRole() {
        XCTAssertEqual(
            SubagentRole.fromToolName("functions.mcp__coderide__coderide_subagent_reviewer"),
            .reviewer
        )
    }
}
