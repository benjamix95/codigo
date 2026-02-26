import Foundation

enum CLIProfileProvisioner {
    static func baseProfilesDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Codigo", isDirectory: true)
            .appendingPathComponent("CLIProfiles", isDirectory: true)
    }

    static func ensureProfile(provider: CLIProviderKind, accountId: UUID) -> String {
        let providerDir = baseProfilesDir().appendingPathComponent(provider.rawValue, isDirectory: true)
        let profile = providerDir.appendingPathComponent(accountId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        // Seed provider-specific config files
        if provider == .codex {
            seedCodexProfile(at: profile)
        }

        return profile.path
    }

    static func environmentOverrides(provider: CLIProviderKind, profilePath: String, secret: String?) -> [String: String] {
        var env: [String: String] = [:]
        switch provider {
        case .codex:
            env["CODEX_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["OPENAI_API_KEY"] = secret }
        case .claude:
            env["CLAUDE_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["ANTHROPIC_API_KEY"] = secret }
        case .gemini:
            env["GEMINI_CONFIG_DIR"] = profilePath
            if let secret, !secret.isEmpty { env["GOOGLE_API_KEY"] = secret }
        }
        return env
    }

    /// Re-seed config files for an existing Codex profile (e.g. after MCP server binary is rebuilt).
    /// Unlike initial seeding, this overwrites existing files to ensure they're up-to-date.
    static func reseedCodexProfile(at profileURL: URL) {
        // Force-write config.toml with latest MCP server path
        let configURL = profileURL.appendingPathComponent("config.toml")
        try? FileManager.default.removeItem(at: configURL)
        seedCodexConfigToml(at: profileURL)

        // Force-write instructions.md with latest template
        let instructionsURL = profileURL.appendingPathComponent("instructions.md")
        try? FileManager.default.removeItem(at: instructionsURL)
        seedCodexInstructionsMd(at: profileURL)
    }

    // MARK: - Codex Profile Seeding

    /// Resolves the path to the bundled coderide-mcp-server binary.
    static func mcpServerBinaryPath() -> String? {
        // Check inside the app bundle first
        if let bundled = Bundle.main.url(forResource: "coderide-mcp-server", withExtension: nil)?.path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        // Fallback: look for it adjacent to the main executable
        if let execURL = Bundle.main.executableURL {
            let sibling = execURL.deletingLastPathComponent().appendingPathComponent("coderide-mcp-server")
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling.path
            }
        }
        // Fallback: swift build debug output
        let debugBuild = baseProfilesDir()
            .deletingLastPathComponent().deletingLastPathComponent() // up to App Support
            .appendingPathComponent("CoderEngine/.build/debug/coderide-mcp-server")
        if FileManager.default.isExecutableFile(atPath: debugBuild.path) {
            return debugBuild.path
        }
        return nil
    }

    private static func seedCodexProfile(at profileURL: URL) {
        seedCodexConfigToml(at: profileURL)
        seedCodexInstructionsMd(at: profileURL)
    }

    private static func seedCodexConfigToml(at profileURL: URL) {
        let configURL = profileURL.appendingPathComponent("config.toml")
        // Don't overwrite if user has customized it
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        var configLines = [
            "# CoderIDE Codex Profile — auto-generated",
            "sandbox_mode = \"danger-full-access\"",
            "",
            "[sandbox_workspace_write]",
            "network_access = true",
        ]

        // Register coderide-mcp-server if binary is available
        if let mcpPath = mcpServerBinaryPath() {
            configLines += [
                "",
                "[mcp_servers.coderide]",
                "command = \"\(mcpPath)\"",
                "args = [ \"--workspace\", \".\" ]",
            ]
        }

        let content = configLines.joined(separator: "\n") + "\n"
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func seedCodexInstructionsMd(at profileURL: URL) {
        let instructionsURL = profileURL.appendingPathComponent("instructions.md")
        guard !FileManager.default.fileExists(atPath: instructionsURL.path) else { return }

        let content = codexInstructionsTemplate
        try? content.write(to: instructionsURL, atomically: true, encoding: .utf8)
    }

    /// The instructions.md template for Codex profiles.
    /// This bridges Codex CLI's native tools with CoderIDE's UI markers.
    /// Codex will load this automatically from CODEX_HOME/instructions.md.
    static let codexInstructionsTemplate = """
    # CoderIDE Integration

    You are running inside CoderIDE. In addition to your normal tools (apply_patch, shell),
    you have access to **coderide MCP tools** (prefixed with `coderide_`). Prefer these
    tools over shell commands for file operations and code search — they are faster, safer,
    and integrated with the IDE.

    ## MCP Tools Available (via coderide server)

    ### File Operations
    - `coderide_read` — Read file contents. Always read before editing.
    - `coderide_read_range` — Read specific line range from a file.
    - `coderide_list_dir` — List files/directories.
    - `coderide_write` — Write/create a file with full content.
    - `coderide_create_file` — Create a new file (fails if exists).
    - `coderide_str_replace` — Replace exact string in a file (preferred for edits).
    - `coderide_regex_replace` — Regex-based find-and-replace in a file.

    ### Search & Navigation
    - `coderide_grep` — Regex search across files.
    - `coderide_glob` — Find files by glob pattern.
    - `coderide_find_files` — Fuzzy file name search.
    - `coderide_codebase_search` — Semantic search ("where is auth handled?").
    - `coderide_find_symbol` — Find symbol definitions by name.
    - `coderide_find_references` — Find all references to a symbol.
    - `coderide_file_outline` — Get file structure outline.

    ### Diagnostics
    - `coderide_diagnostics` — Full build diagnostics (errors/warnings).
    - `coderide_read_lints` — Quick lint check without full build.
    - `coderide_git_diff` — Show git diff.

    ### Web
    - `coderide_web_search` — Search the web.
    - `coderide_web_fetch` — Fetch a web page as Markdown.

    ## Workflow

    1. **INVESTIGATE** — Use `coderide_grep`, `coderide_codebase_search`, `coderide_find_symbol`,
       `coderide_read`, `coderide_file_outline` to understand the problem BEFORE making changes.
    2. **PLAN** — For multi-step tasks, emit progress markers (see below).
    3. **RESOLVE** — Use `coderide_str_replace` for surgical edits. Only use `coderide_write`
       for new files or complete rewrites. Always `coderide_read` before editing.
    4. **VERIFY** — Use `coderide_read_lints` (fast) or `coderide_diagnostics` (full build).

    ## IDE Progress Markers

    Emit these text markers inline in your response to update the CoderIDE UI:

    ### Todo List (for multi-step tasks with 3+ steps)
    ```
    [CODERIDE:todo_write|title=Task description|status=pending|priority=medium]
    [CODERIDE:todo_write|title=Task description|status=in_progress]
    [CODERIDE:todo_write|title=Task description|status=completed]
    ```

    ### Plan Steps
    ```
    [CODERIDE:plan_step|step_id=1|status=running|title=Analysis]
    [CODERIDE:plan_step|step_id=1|status=completed|title=Analysis]
    ```

    ### Debug Mode
    ```
    [CODERIDE:debug_panel|action=open|phase=analyzing]
    [CODERIDE:debug_panel|action=phase|phase=verifying]
    [CODERIDE:debug_panel|action=resolve|phase=Fixed the issue]
    ```

    ## Rules
    - ALWAYS read a file before editing it.
    - Prefer `coderide_str_replace` over `apply_patch` for targeted edits.
    - Prefer `coderide_grep`/`coderide_find_symbol` over shell `grep`/`find`.
    - Use shell (`bash`) only for git operations, running builds, installing deps.
    - Emit todo markers for any task with 3+ steps.
    - Do NOT stop until the task is fully resolved.
    """
}
