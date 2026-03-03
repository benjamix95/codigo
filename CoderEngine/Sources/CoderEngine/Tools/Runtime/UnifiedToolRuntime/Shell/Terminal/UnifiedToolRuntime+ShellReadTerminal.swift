import Foundation

extension UnifiedToolRuntime {

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
}
