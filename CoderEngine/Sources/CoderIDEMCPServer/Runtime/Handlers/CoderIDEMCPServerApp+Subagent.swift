import CoderEngine
import Foundation

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

        return await withTaskGroup(of: SubagentResult.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        process.waitUntilExit()
                        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let outStr = String(data: outData, encoding: .utf8) ?? ""
                        let errStr = String(data: errData, encoding: .utf8) ?? ""

                        let exitCode = process.terminationStatus
                        var result = outStr
                        if !errStr.isEmpty && result.isEmpty {
                            result = errStr
                        }
                        if result.isEmpty {
                            result = exitCode == 0
                                ? "Subagent completed successfully."
                                : "Subagent failed (exit \(exitCode))."
                        }

                        let truncated = result.count > 100_000
                            ? String(result.prefix(100_000)) + "\n... [truncated]"
                            : result

                        continuation.resume(returning: SubagentResult(
                            output: truncated,
                            isError: exitCode != 0
                        ))
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    if process.isRunning { process.interrupt() }
                }
                return SubagentResult(
                    output: "Subagent \(resolvedRole.displayName) timed out after \(Int(timeout))s.",
                    isError: true
                )
            }

            let firstResult = await group.next()!
            group.cancelAll()
            return firstResult
        }
    }

    private static func resolveAvailableCLI(readOnly: Bool) -> String? {
        let preferredNames = SubagentCLIConfig.preferredBackendNames(readOnly: readOnly)
        let byNameCandidates: [String: [String]] = [
            "codex": ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"],
            "claude": ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"],
        ]

        for name in preferredNames {
            for path in byNameCandidates[name] ?? [] {
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                if SubagentCLIConfig.supportsSandboxExpectations(cliPath: path, readOnly: readOnly) {
                    return path
                }
            }
        }

        for name in preferredNames {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            proc.arguments = [name]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
}
