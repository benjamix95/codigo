import Foundation

extension UnifiedToolRuntime {
    func executeRunTests(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let target = (call.args["target"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = (call.args["filter"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMs = max(1_000, Int(call.args["timeout_ms"] ?? "") ?? context.policy.timeoutMs)
        var command = "swift test"
        if !target.isEmpty { command += " --filter '\(shellEscaped(target))'" }
        if !filter.isEmpty, target.isEmpty { command += " --filter '\(shellEscaped(filter))'" }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Run tests",
            timeoutMs: timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeBuildProject(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let configuration = (call.args["configuration"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (call.args["target"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMs = max(1_000, Int(call.args["timeout_ms"] ?? "") ?? context.policy.timeoutMs)
        var command = "swift build"
        if !configuration.isEmpty {
            command += " -c \(shellEscaped(configuration))"
        }
        if !target.isEmpty {
            command += " --target '\(shellEscaped(target))'"
        }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Build project",
            timeoutMs: timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeListProcesses(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let filter = (call.args["filter"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let command = filter.isEmpty
            ? "ps aux | head -n 200"
            : "ps aux | rg -i '\(shellEscaped(filter))' | head -n 200"
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "List processes",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeTailLog(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let lines = max(1, min(2_000, Int(call.args["lines"] ?? "200") ?? 200))
        guard let rawPath = call.args["path"], !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure("path is required", errorCode: "validation", startDate: startDate)
        }
        do {
            let path = try resolveRequiredPath(rawPath, context: context)
            let cmd = "tail -n \(lines) '\(shellEscaped(path))'"
            return await runBash(
                command: cmd,
                cwd: context.workspaceContext.workspacePath,
                startDate: startDate,
                title: "Tail log",
                timeoutMs: context.policy.timeoutMs,
                maxOutputBytes: context.policy.maxBashOutputBytes,
                policy: context.policy
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private static let longRunningPatterns: [String] = [
        "npm run", "npm start", "npm test", "yarn ", "pnpm ",
        "swift build", "swift test", "swift run",
        "cargo build", "cargo run", "cargo test",
        "make", "cmake", "gradle",
        "python ", "python3 ", "node ",
        "docker ", "kubectl ",
        "xcodebuild", "fastlane",
        "serve", "watch", "dev"
    ]

    func isLongRunningCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return Self.longRunningPatterns.contains(where: { lower.contains($0) })
    }

    func runBash(
        command: String,
        cwd: URL,
        startDate: Date,
        title: String,
        timeoutMs: Int,
        maxOutputBytes: Int,
        policy: ToolRuntimePolicy
    ) async -> ToolResult {
        do {
            try validateShell(command: command, policy: policy)

            if isLongRunningCommand(command), let bridge = terminalBridge {
                let label = "Agent: \(command.prefix(40))"
                let result = await bridge.executeInTerminal(
                    command: command,
                    cwd: cwd.path,
                    label: label
                )
                let output = truncate(String(result.output.prefix(maxOutputBytes)), maxBytes: maxOutputBytes)
                if result.exitCode == 0 {
                    return success([
                        "title": title,
                        "command": command,
                        "cwd": cwd.path,
                        "output": output,
                        "ran_in_terminal": "true"
                    ], startDate: startDate)
                }
                return failure(
                    "exit \(result.exitCode): \(truncate(output, maxBytes: 3_000))",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: [
                        "title": title,
                        "command": command,
                        "cwd": cwd.path,
                        "output": output,
                        "ran_in_terminal": "true"
                    ]
                )
            }

            let controller = self.executionController
            let scope = self.executionScope
            let result = try await withThrowingTaskGroup(
                of: (output: [String], terminationStatus: Int32).self
            ) { group in
                group.addTask {
                    try await ProcessRunner.runCollecting(
                        executable: "/bin/zsh",
                        arguments: ["-lc", command],
                        workingDirectory: cwd,
                        executionController: controller,
                        scope: scope
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1_000, timeoutMs)) * 1_000_000)
                    controller?.terminate(scope: scope)
                    throw ToolRuntimeError.timeout(tool: "bash", ms: timeoutMs)
                }
                guard let first = try await group.next() else {
                    throw ToolRuntimeError.transport("No response from process")
                }
                group.cancelAll()
                return first
            }

            let output = truncate(result.output.joined(separator: "\n"), maxBytes: maxOutputBytes)
            if result.terminationStatus == 0 {
                return success([
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": output
                ], startDate: startDate)
            }
            return failure(
                "exit \(result.terminationStatus): \(truncate(output, maxBytes: 3_000))",
                errorCode: "transport",
                startDate: startDate,
                payload: [
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": output
                ]
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path,
                "timeout_ms": "\(timeoutMs)"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path
            ])
        }
    }

    // MARK: - Read Terminal
}
