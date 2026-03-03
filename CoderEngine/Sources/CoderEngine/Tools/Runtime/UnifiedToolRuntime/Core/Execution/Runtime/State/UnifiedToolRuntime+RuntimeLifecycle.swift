import Foundation

extension UnifiedToolRuntime {
    public func setBrowserBridge(_ bridge: (any BrowserBridge)?) {
        self.browserBridge = bridge
    }

    public func setTerminalBridge(_ bridge: (any TerminalBridge)?) {
        self.terminalBridge = bridge
    }

    public func debugSnapshot() -> ToolRuntimeDebugSnapshot {
        ToolRuntimeDebugSnapshot(
            hasCodebaseIndex: codebaseIndex != nil,
            workspacePaths: workspacePaths.map(\.path),
            excludedPaths: excludedPaths,
            executionScope: executionScope
        )
    }

    func ensureIndexTools(for context: ToolExecutionContext) async -> CodebaseIndexTools {
        if let indexTools {
            return indexTools
        }

        let index = codebaseIndex ?? CodebaseIndex()
        codebaseIndex = index
        let tools = CodebaseIndexTools(index: index)
        indexTools = tools

        let requestedPaths = preferredWorkspacePaths(for: context)
        if !requestedPaths.isEmpty {
            let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
        }

        return tools
    }

    /// Run an external process and return (stdout, stderr, exitCode).
    /// A lightweight wrapper around ProcessRunner for tools that need simple exec.
    func shellExec(
        args: [String],
        cwd: String,
        timeout: Int = 30_000
    ) async -> (String, String, Int32) {
        guard !args.isEmpty else { return ("", "argument list is empty", 1) }
        let executable = args[0]
        let arguments = Array(args.dropFirst())
        do {
            let result = try await ProcessRunner.runCollecting(
                executable: executable,
                arguments: arguments,
                workingDirectory: URL(fileURLWithPath: cwd),
                executionController: executionController,
                scope: executionScope
            )
            let stdout = result.output.joined(separator: "\n")
            return (stdout, "", result.terminationStatus)
        } catch {
            return ("", error.localizedDescription, 1)
        }
    }

    func runShellCommand(_ command: String, timeout: Int = 15_000) async -> String {
        let (stdout, _, _) = await shellExec(
            args: ["/bin/zsh", "-lc", command],
            cwd: ".",
            timeout: timeout
        )
        return stdout
    }

    /// Tools that modify files and should trigger a codebase reindex.
    static let fileChangingTools: Set<String> = [
        "edit", "write", "str_replace", "create_file", "delete_file",
        "parallel_apply", "regex_replace", "rename_symbol",
        "find_and_replace_all", "undo_edit", "write_json",
        "apply_diff", "debug_mark", "debug_clean",
    ]

    /// Resets per-round budget counters. Call at the beginning of each tool round.
    public func resetRoundCounters() {
        toolCallsInCurrentRound = 0
        toolCallCountByName = [:]
    }

    /// Re-indexes a single file after it has been modified by a tool.
    func reindexModifiedFile(call: ToolCall, context: ToolExecutionContext) async {
        guard let index = codebaseIndex else { return }
        let path = call.args["path"] ?? call.args["file_path"] ?? call.args["file"] ?? call.args["target_path"] ?? ""
        guard !path.isEmpty else { return }

        let workspacePath = context.workspaceContext.workspacePath.path
        let absolutePath: String
        if (path as NSString).isAbsolutePath {
            absolutePath = path
        } else {
            absolutePath = (workspacePath as NSString).appendingPathComponent(path)
        }

        let relativePath: String
        if absolutePath.hasPrefix(workspacePath) {
            relativePath = String(absolutePath.dropFirst(workspacePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relativePath = path
        }

        await index.indexSingleFile(absolutePath: absolutePath, relativePath: relativePath)
    }
}
