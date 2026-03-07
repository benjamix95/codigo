import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Pure-function helpers shared between CoderIDEMCPServer and tests.
/// These have no MCP dependencies — only Foundation and SubagentRole.
public enum SubagentCLIConfig {
    public static let constrainedPATH = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
    public static let knownProviderIDs = ["codex", "claude", "gemini"]

    /// Whether a subagent role should run in read-only sandbox mode.
    /// Explorer, reviewer, bugHunter, and securityAuditor only analyze — they never edit files.
    public static func isReadOnly(_ role: SubagentRole) -> Bool {
        switch role {
        case .explorer, .reviewer, .bugHunter, .securityAuditor:
            return true
        case .coder, .debugger, .testWriter, .docWriter:
            return false
        }
    }

    /// Timeout in seconds: read-only roles get a shorter budget.
    public static func timeout(for role: SubagentRole) -> TimeInterval {
        // Keep subagent execution safely under common MCP tools/call deadlines (120s),
        // otherwise the client can time out before this process reports its own timeout.
        isReadOnly(role) ? 95 : 110
    }

    /// Preferred CLI backend names by capability.
    /// - Read-only roles: codex first, then claude.
    /// - Write roles: codex only (workspace sandbox support required).
    public static func preferredBackendNames(readOnly: Bool) -> [String] {
        readOnly ? ["codex", "claude"] : ["codex"]
    }

    /// Whether the selected CLI backend can satisfy sandbox expectations.
    public static func supportsSandboxExpectations(cliPath: String, readOnly: Bool) -> Bool {
        let basename = URL(fileURLWithPath: cliPath).lastPathComponent.lowercased()
        switch basename {
        case "codex":
            return true
        case "claude":
            return readOnly
        default:
            return false
        }
    }

    /// Build CLI arguments for a given backend (codex, claude, gemini).
    public static func buildCLIArgs(
        cliPath: String,
        prompt: String,
        workspacePath: String,
        readOnly: Bool
    ) -> [String] {
        let basename = URL(fileURLWithPath: cliPath).lastPathComponent.lowercased()

        switch basename {
        case "codex":
            var args = ["exec", "--full-auto"]
            if readOnly {
                args += ["--sandbox", "read-only"]
            } else {
                args += ["--sandbox", "workspace-write"]
            }
            args += ["--cd", workspacePath, prompt]
            return args

        case "claude":
            var args = ["-p", prompt, "--output-format", "text"]
            if readOnly {
                args.append(contentsOf: ["--allowedTools", "Read,Search,Glob,Grep"])
            }
            return args

        case "gemini":
            return ["-p", prompt]

        default:
            return [prompt]
        }
    }
}

public struct SubagentCLIRunResult: Sendable, Equatable {
    public let output: String
    public let isError: Bool
    public let providerID: String?
    public let cliPath: String?
    public let durationMs: Int

    public init(
        output: String,
        isError: Bool,
        providerID: String?,
        cliPath: String?,
        durationMs: Int
    ) {
        self.output = output
        self.isError = isError
        self.providerID = providerID
        self.cliPath = cliPath
        self.durationMs = durationMs
    }
}

public enum SubagentCLIRunner {
    public static func run(
        role: SubagentRole,
        task: String,
        workspacePath: String
    ) async -> SubagentCLIRunResult {
        let startedAt = Date()

        guard let backend = await SubagentBackendResolver.selectBackend(for: role) else {
            let installHint = SubagentCLIConfig.isReadOnly(role)
                ? "Install codex or claude CLI."
                : "Install codex CLI (required for workspace-write sandbox)."
            return SubagentCLIRunResult(
                output: "No compatible CLI backend available for subagent execution. \(installHint)",
                isError: true,
                providerID: nil,
                cliPath: nil,
                durationMs: elapsedMs(since: startedAt)
            )
        }

        let prompt = SubagentPromptBuilder.build(role: role, task: task)
        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: backend.cliPath,
            prompt: prompt,
            workspacePath: workspacePath,
            readOnly: SubagentCLIConfig.isReadOnly(role)
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: backend.cliPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["PATH"] = SubagentCLIConfig.constrainedPATH
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            await SubagentProviderHealthRuntime.shared.recordExecution(
                providerID: backend.providerID,
                success: false
            )
            return SubagentCLIRunResult(
                output: "Failed to launch subagent CLI: \(error.localizedDescription)",
                isError: true,
                providerID: backend.providerID,
                cliPath: backend.cliPath,
                durationMs: elapsedMs(since: startedAt)
            )
        }

        let waitTask = Task<Int32, Never> {
            process.waitUntilExit()
            return process.terminationStatus
        }
        let stdoutTask = Task<Data, Never> {
            stdout.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task<Data, Never> {
            stderr.fileHandleForReading.readDataToEndOfFile()
        }

        let didTimeout = await timedOut(
            process: process,
            waitTask: waitTask,
            timeoutSeconds: backend.timeoutSeconds
        )
        if didTimeout {
            await terminateProcessIfNeeded(process)
            _ = await waitTask.value
            stdoutTask.cancel()
            stderrTask.cancel()
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            await SubagentProviderHealthRuntime.shared.recordExecution(
                providerID: backend.providerID,
                success: false
            )

            return SubagentCLIRunResult(
                output: "Subagent \(role.displayName) timed out after \(Int(backend.timeoutSeconds))s.",
                isError: true,
                providerID: backend.providerID,
                cliPath: backend.cliPath,
                durationMs: elapsedMs(since: startedAt)
            )
        }

        let exitCode = await waitTask.value
        let outputData = await stdoutTask.value
        let errorData = await stderrTask.value
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        let errorString = String(data: errorData, encoding: .utf8) ?? ""

        var resultText = outputString
        if !errorString.isEmpty && resultText.isEmpty {
            resultText = errorString
        }
        if resultText.isEmpty {
            resultText = exitCode == 0
                ? "Subagent completed successfully."
                : "Subagent failed (exit \(exitCode))."
        }
        await SubagentProviderHealthRuntime.shared.recordExecution(
            providerID: backend.providerID,
            success: exitCode == 0
        )

        return SubagentCLIRunResult(
            output: truncateOutput(resultText),
            isError: exitCode != 0,
            providerID: backend.providerID,
            cliPath: backend.cliPath,
            durationMs: elapsedMs(since: startedAt)
        )
    }

    private static func timedOut(
        process: Process,
        waitTask: Task<Int32, Never>,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        let timedOutByDeadline = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await waitTask.value
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if timedOutByDeadline && !process.isRunning {
            return false
        }
        return timedOutByDeadline
    }

    private static func terminateProcessIfNeeded(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(nanoseconds: 300_000_000)
        if process.isRunning {
            process.interrupt()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
#if canImport(Darwin)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
#endif
    }

    private static func truncateOutput(_ output: String) -> String {
        if output.count > 100_000 {
            return String(output.prefix(100_000)) + "\n... [truncated]"
        }
        return output
    }

    private static func elapsedMs(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}
