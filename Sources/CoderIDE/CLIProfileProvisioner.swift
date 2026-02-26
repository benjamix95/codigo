import Foundation

enum CLIProfileProvisioner {
    private static let mcpServerPathOverrideEnv = "CODERIDE_MCP_SERVER_PATH"

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
            ensureCodexProfileFiles(at: profile, overwrite: false)
        } else if provider == .claude {
            ensureClaudeProfileFiles(at: profile)
        }

        return profile.path
    }

    static func environmentOverrides(provider: CLIProviderKind, profilePath: String, secret: String?) -> [String: String] {
        var env: [String: String] = [:]
        switch provider {
        case .codex:
            // Self-heal old/broken profiles where config.toml/AGENTS.md were deleted
            // or where the MCP server block is missing/outdated.
            ensureCodexProfileFiles(at: URL(fileURLWithPath: profilePath, isDirectory: true), overwrite: false)
            env["CODEX_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["OPENAI_API_KEY"] = secret }
        case .claude:
            let profileURL = URL(fileURLWithPath: profilePath, isDirectory: true)
            ensureClaudeProfileFiles(at: profileURL)
            env["HOME"] = profilePath
            env["CLAUDE_HOME"] = profileURL
                .appendingPathComponent(".claude", isDirectory: true)
                .path
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
        ensureCodexProfileFiles(at: profileURL, overwrite: true)
    }

    /// Repairs a Codex profile without overwriting user customizations.
    static func selfHealCodexProfile(at profileURL: URL) {
        ensureCodexProfileFiles(at: profileURL, overwrite: false)
    }

    private static func ensureClaudeProfileFiles(at profileURL: URL) {
        try? FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        let claudeHome = profileURL.appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
    }

    // MARK: - Codex Profile Seeding

    /// Resolves the path to the bundled coderide-mcp-server binary.
    static func mcpServerBinaryPath() -> String? {
        // Fast-path explicit override (used by tests and advanced debugging).
        let overridePath = ProcessInfo.processInfo.environment[mcpServerPathOverrideEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !overridePath.isEmpty, FileManager.default.isExecutableFile(atPath: overridePath) {
            return overridePath
        }

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
        // Dev fallback: locate the binary in CoderEngine/.build from workspace root.
        if let workspaceRoot = locateWorkspaceRoot() {
            if let fromEngineBuild = findMCPBinary(in: workspaceRoot.appendingPathComponent("CoderEngine/.build", isDirectory: true)) {
                return fromEngineBuild
            }
            if let fromRootBuild = findMCPBinary(in: workspaceRoot.appendingPathComponent(".build", isDirectory: true)) {
                return fromRootBuild
            }
        }
        // Legacy fallback near App Support.
        let appSupportBuild = baseProfilesDir()
            .deletingLastPathComponent().deletingLastPathComponent() // up to App Support
            .appendingPathComponent("CoderEngine/.build", isDirectory: true)
        if let fromBuild = findMCPBinary(in: appSupportBuild) {
            return fromBuild
        }
        // Last resort: look in PATH.
        if let fromPath = findBinaryOnPATH(named: "coderide-mcp-server") {
            return fromPath
        }
        return nil
    }

    private static func locateWorkspaceRoot() -> URL? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let marker = current.appendingPathComponent("CoderEngine/Package.swift")
            if FileManager.default.fileExists(atPath: marker.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private static func findMCPBinary(in buildRoot: URL) -> String? {
        guard FileManager.default.fileExists(atPath: buildRoot.path) else { return nil }

        let directCandidates = [
            buildRoot.appendingPathComponent("debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("release/coderide-mcp-server"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/release/coderide-mcp-server"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/release/coderide-mcp-server"),
        ]
        for candidate in directCandidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }

        guard let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "coderide-mcp-server",
               FileManager.default.isExecutableFile(atPath: fileURL.path) {
                return fileURL.path
            }
        }
        return nil
    }

    private static func findBinaryOnPATH(named binaryName: String) -> String? {
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in pathVar.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(component), isDirectory: true)
                .appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    private static func ensureCodexProfileFiles(at profileURL: URL, overwrite: Bool) {
        try? FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        seedCodexConfigToml(at: profileURL, overwrite: overwrite)
        seedCodexAgentsMd(at: profileURL, overwrite: overwrite)
        // Legacy compatibility for older profiles/tooling still looking for instructions.md.
        seedCodexInstructionsMd(at: profileURL, overwrite: overwrite)
    }

    private static func seedCodexConfigToml(at profileURL: URL, overwrite: Bool) {
        let configURL = profileURL.appendingPathComponent("config.toml")
        // Don't overwrite user customizations unless explicitly requested.
        // Still self-heal MCP block for existing configs.
        if FileManager.default.fileExists(atPath: configURL.path), !overwrite {
            repairCodexConfigTomlIfNeeded(at: configURL)
            return
        }

        var configLines = [
            "# CoderIDE Codex Profile — auto-generated",
            "sandbox_mode = \"danger-full-access\"",
            "",
            "[sandbox_workspace_write]",
            "network_access = true",
        ]

        // Register coderide-mcp-server if binary is available.
        if let mcpPath = mcpServerBinaryPath() {
            configLines.append("")
            configLines.append(contentsOf: coderideMCPSectionLines(binaryPath: mcpPath))
        }

        let content = configLines.joined(separator: "\n") + "\n"
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func repairCodexConfigTomlIfNeeded(at configURL: URL) {
        guard let existing = try? String(contentsOf: configURL, encoding: .utf8),
              let mcpPath = mcpServerBinaryPath() else {
            return
        }

        let lines = existing.components(separatedBy: .newlines)
        let updated = upsertCoderideMCPSection(in: lines, binaryPath: mcpPath)
        let normalizedExisting = existing.hasSuffix("\n") ? existing : existing + "\n"
        let normalizedUpdated = updated.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        guard normalizedUpdated != normalizedExisting else { return }
        try? normalizedUpdated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func upsertCoderideMCPSection(in lines: [String], binaryPath: String) -> [String] {
        let sectionHeader = "[mcp_servers.coderide]"
        let replacement = coderideMCPSectionLines(binaryPath: binaryPath)
        var output = lines

        if let start = output.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) {
            var end = start + 1
            while end < output.count {
                let trimmed = output[end].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    break
                }
                end += 1
            }
            output.replaceSubrange(start..<end, with: replacement)
            return output
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }
        if !output.isEmpty {
            output.append("")
        }
        output.append(contentsOf: replacement)
        return output
    }

    private static func coderideMCPSectionLines(binaryPath: String) -> [String] {
        [
            "[mcp_servers.coderide]",
            "command = \"\(binaryPath)\"",
            "args = [ \"--workspace\", \".\" ]",
        ]
    }

    private static func seedCodexAgentsMd(at profileURL: URL, overwrite: Bool) {
        let agentsURL = profileURL.appendingPathComponent("AGENTS.md")
        if !overwrite && FileManager.default.fileExists(atPath: agentsURL.path) {
            return
        }

        let content = codexInstructionsTemplate
        try? content.write(to: agentsURL, atomically: true, encoding: .utf8)
    }

    private static func seedCodexInstructionsMd(at profileURL: URL, overwrite: Bool) {
        let instructionsURL = profileURL.appendingPathComponent("instructions.md")
        if !overwrite && FileManager.default.fileExists(atPath: instructionsURL.path) {
            return
        }

        let content = codexInstructionsTemplate
        try? content.write(to: instructionsURL, atomically: true, encoding: .utf8)
    }

    /// The instructions.md template for Codex profiles.
    /// This bridges Codex CLI's native tools with CoderIDE's UI markers.
    /// Main modern entrypoint is CODEX_HOME/AGENTS.md (also generated above).
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
