import CoderEngine
import Foundation
#if canImport(Darwin)
import Darwin
#endif

extension CoderIDEMCPServerApp {

    // MARK: - Subagent Execution
    struct SubagentResult {
        let output: String
        let isError: Bool
    }

    static func executeSubagentViaCLI(
        role: String,
        task: String,
        workspacePath: String
    ) async -> SubagentResult {
        guard let resolvedRole = SubagentRole.fromToolName(role) else {
            return SubagentResult(
                output: "Unknown subagent role: \(role). Valid roles: \(SubagentRole.allToolNames.joined(separator: ", "))",
                isError: true
            )
        }

        let prompt = SubagentPromptBuilder.build(role: resolvedRole, task: task)
        let readOnly = SubagentCLIConfig.isReadOnly(resolvedRole)
        let timeout = SubagentCLIConfig.timeout(for: resolvedRole)

        let cliPath = resolveAvailableCLI(readOnly: readOnly)
        guard let cliPath else {
            let installHint = readOnly
                ? "Install codex or claude CLI."
                : "Install codex CLI (required for workspace-write sandbox)."
            return SubagentResult(
                output: "No compatible CLI backend available for subagent execution. \(installHint)",
                isError: true
            )
        }
        guard SubagentCLIConfig.supportsSandboxExpectations(cliPath: cliPath, readOnly: readOnly) else {
            return SubagentResult(
                output: "Selected CLI backend does not satisfy sandbox requirements for this subagent role.",
                isError: true
            )
        }

        let args = SubagentCLIConfig.buildCLIArgs(
            cliPath: cliPath,
            prompt: prompt,
            workspacePath: workspacePath,
            readOnly: readOnly
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["PATH"] = SubagentCLIConfig.constrainedPATH
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return SubagentResult(
                output: "Failed to launch subagent CLI: \(error.localizedDescription)",
                isError: true
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

        let timedOutByDeadline = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await waitTask.value
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        var didTimeout = timedOutByDeadline
        if didTimeout && !process.isRunning {
            didTimeout = false
        }

        if didTimeout {
            await terminateProcessIfNeeded(process)
            waitTask.cancel()
            stdoutTask.cancel()
            stderrTask.cancel()
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()

            let timeoutMessage = "Subagent \(resolvedRole.displayName) timed out after \(Int(timeout))s."
            return SubagentResult(output: timeoutMessage, isError: true)
        }

        let exitCode = await waitTask.value
        let outData = await stdoutTask.value
        let errData = await stderrTask.value
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        var result = outStr
        if !errStr.isEmpty && result.isEmpty {
            result = errStr
        }
        if result.isEmpty {
            result = exitCode == 0
                ? "Subagent completed successfully."
                : "Subagent failed (exit \(exitCode))."
        }
        let truncated = truncateOutput(result)

        return SubagentResult(
            output: truncated,
            isError: exitCode != 0
        )
    }

    private static func resolveAvailableCLI(readOnly: Bool) -> String? {
        let preferredNames = SubagentCLIConfig.preferredBackendNames(readOnly: readOnly)
        let byNameCandidates: [String: [String]] = [
            "codex": ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"],
            "claude": ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"],
            "gemini": ["/usr/local/bin/gemini", "/opt/homebrew/bin/gemini"],
        ]
        let fallbackNames = byNameCandidates.keys
            .filter { !preferredNames.contains($0) }
            .sorted()
        let candidateOrder = preferredNames + fallbackNames

        for name in candidateOrder {
            for path in byNameCandidates[name] ?? [] {
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                if SubagentCLIConfig.supportsSandboxExpectations(cliPath: path, readOnly: readOnly) {
                    return path
                }
            }
        }

        for name in candidateOrder {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            proc.arguments = [name]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !path.isEmpty,
                       SubagentCLIConfig.supportsSandboxExpectations(cliPath: path, readOnly: readOnly) {
                        return path
                    }
                }
            } catch {
                continue
            }
        }
        return nil
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
}
