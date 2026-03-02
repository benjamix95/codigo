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

    func executeReadTerminal(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = terminalBridge else {
            return failure(
                "Terminal bridge not available",
                errorCode: "transport",
                startDate: startDate
            )
        }
        let sessionId = call.args["session_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastN = max(500, min(32_000, Int(call.args["last_n"] ?? "8000") ?? 8_000))
        let emptySessionId: String? = (sessionId?.isEmpty == true) ? nil : sessionId

        let output: String
        if call.args["all_sessions"] == "true" {
            output = await bridge.allSessionsSummary(lastN: lastN)
        } else {
            output = await bridge.readTerminalOutput(sessionId: emptySessionId, lastN: lastN)
        }

        if output.isEmpty {
            return success(["output": "(no terminal output)", "detail": "empty"], startDate: startDate)
        }
        return success(["output": output, "detail": "\(output.count) chars"], startDate: startDate)
    }

    // MARK: - Web Search

    func executeAttemptCompletion(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let result = call.args["result"] ?? "Task completed"
        let command = call.args["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !command.isEmpty {
            // Run verification command
            let verifyResult = await runBash(
                command: command,
                cwd: context.workspaceContext.workspacePath,
                startDate: startDate,
                title: "Verification",
                timeoutMs: context.policy.timeoutMs,
                maxOutputBytes: context.policy.maxBashOutputBytes,
                policy: context.policy
            )
            if !verifyResult.ok {
                let output = verifyResult.payload["output"] ?? ""
                return failure(
                    "Verification failed: \(truncate(output, maxBytes: 2000))",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: [
                        "title": "attempt_completion (verification failed)",
                        "command": command,
                        "output": output
                    ]
                )
            }
        }

        return success([
            "title": "Task completed",
            "output": result,
            "detail": command.isEmpty ? "Completion signaled" : "Verified with: \(command)"
        ], startDate: startDate)
    }

    // MARK: - New Tool: diagnostics

    func executeDiagnostics(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let manager = (call.args["manager"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Auto-detect project type if not specified
        let buildCommand: String
        let projectType: String
        if !manager.isEmpty {
            switch manager {
            case "swift": buildCommand = "swift build 2>&1"; projectType = "Swift"
            case "npm": buildCommand = "npm run build 2>&1 || true"; projectType = "Node/npm"
            case "cargo": buildCommand = "cargo check 2>&1"; projectType = "Rust/Cargo"
            case "go": buildCommand = "go build ./... 2>&1"; projectType = "Go"
            default: buildCommand = "swift build 2>&1"; projectType = manager
            }
        } else {
            // Auto-detect
            let wsPath = context.workspaceContext.workspacePath.path
            if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Package.swift")) {
                buildCommand = "swift build 2>&1"
                projectType = "Swift"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("package.json")) {
                buildCommand = "npm run build 2>&1 || true"
                projectType = "Node/npm"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Cargo.toml")) {
                buildCommand = "cargo check 2>&1"
                projectType = "Rust/Cargo"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("go.mod")) {
                buildCommand = "go build ./... 2>&1"
                projectType = "Go"
            } else {
                buildCommand = "swift build 2>&1"
                projectType = "Swift (default)"
            }
        }

        let buildResult = await runBash(
            command: buildCommand,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Diagnostics",
            timeoutMs: max(context.policy.timeoutMs, 120_000),
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )

        let rawOutput = buildResult.payload["output"] ?? ""

        // Parse diagnostics from output
        var errors: [(file: String, line: String, col: String, severity: String, message: String)] = []
        let diagnosticPattern = try? NSRegularExpression(pattern: #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#, options: .anchorsMatchLines)

        if let regex = diagnosticPattern {
            let matches = regex.matches(in: rawOutput, range: NSRange(rawOutput.startIndex..., in: rawOutput))
            for match in matches.prefix(100) {
                guard match.numberOfRanges >= 6 else { continue }
                func extract(_ i: Int) -> String {
                    guard let r = Range(match.range(at: i), in: rawOutput) else { return "" }
                    return String(rawOutput[r])
                }
                errors.append((file: extract(1), line: extract(2), col: extract(3), severity: extract(4), message: extract(5)))
            }
        }

        let errorCount = errors.filter { $0.severity == "error" }.count
        let warningCount = errors.filter { $0.severity == "warning" }.count

        var output = "Project: \(projectType)\n"
        output += "Status: \(buildResult.ok ? "BUILD SUCCESS" : "BUILD FAILED")\n"
        output += "Errors: \(errorCount), Warnings: \(warningCount)\n\n"

        if !errors.isEmpty {
            for diag in errors.prefix(50) {
                let icon = diag.severity == "error" ? "ERROR" : diag.severity == "warning" ? "WARN" : "NOTE"
                output += "[\(icon)] \(diag.file):\(diag.line):\(diag.col) \(diag.message)\n"
            }
            if errors.count > 50 {
                output += "... and \(errors.count - 50) more diagnostics\n"
            }
        } else if !buildResult.ok {
            output += rawOutput
        }

        return ToolResult(
            ok: true,
            payload: [
                "title": "Diagnostics (\(projectType))",
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": buildResult.ok ? "Build OK" : "\(errorCount) errors, \(warningCount) warnings"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    func executeRunSingleTest(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let testName = call.args["test"] ?? call.args["name"] ?? call.args["filter"] ?? ""
        let target = call.args["target"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !testName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "test name/filter is required"], durationMs: 0)
        }

        // Detect project type and build command
        let fm = FileManager.default
        var cmd: [String]
        if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Package.swift")) {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
            if !target.isEmpty { cmd += ["--target", target] }
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("package.json")) {
            cmd = ["/usr/bin/env", "npx", "jest", "--testPathPattern", testName, "--no-coverage"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Cargo.toml")) {
            cmd = ["/usr/bin/env", "cargo", "test", testName, "--", "--nocapture"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("go.mod")) {
            cmd = ["/usr/bin/env", "go", "test", "-run", testName, "-v", "./..."]
        } else {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
        }

        let (output, stderr, exitCode) = await shellExec(args: cmd, cwd: workspace, timeout: 120_000)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let combined = (output + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Also log to debug server
        await debugLogServer.logTestOutput(combined, source: "run_single_test:\(testName)")

        if exitCode == 0 {
            return ToolResult(ok: true, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' passed",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        } else {
            return ToolResult(ok: false, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' failed (exit \(exitCode))",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        }
    }

    // MARK: - Debug Tools
}
