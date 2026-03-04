import Foundation

enum LLDBDAPDebugAdapterSupport {
    static func normalizeExecutionCommand(_ command: String) -> String {
        switch command.lowercased() {
        case "continue", "c", "run":
            return "process continue"
        case "step", "s", "step-in":
            return "thread step-in"
        case "next", "n", "step-over":
            return "thread step-over"
        case "finish", "step-out":
            return "thread step-out"
        default:
            return command
        }
    }

    static func isContinueLikeCommand(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        return lowercased.contains("continue") || lowercased == "run" || lowercased == "c"
    }

    static func isExecutionCommand(_ command: String) -> Bool {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("process continue")
            || normalized.hasPrefix("thread step-in")
            || normalized.hasPrefix("thread step-out")
            || normalized.hasPrefix("thread step-over")
            || normalized == "continue"
            || normalized == "next"
            || normalized == "step"
            || normalized == "finish"
            || normalized == "run"
    }

    static func isRunnableTarget(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    static func inferSessionStatus(
        from output: String,
        exitCode: Int32,
        fallback: NativeDebugStatus
    ) -> NativeDebugStatus {
        guard exitCode == 0 else { return .error }
        let lowercasedOutput = output.lowercased()

        if lowercasedOutput.contains("exited with status")
            || lowercasedOutput.contains("process exited")
            || lowercasedOutput.contains("process no longer exists")
            || lowercasedOutput.contains("process is not running")
            || lowercasedOutput.contains("not running")
        {
            return .stopped
        }

        if lowercasedOutput.contains("process is running")
            || lowercasedOutput.contains("state = running")
            || lowercasedOutput.contains("running, stop reason =")
        {
            return .running
        }

        if lowercasedOutput.contains("stop reason")
            || lowercasedOutput.contains("stopped")
            || lowercasedOutput.contains("hit breakpoint")
            || lowercasedOutput.contains("frame #0")
        {
            return .paused
        }

        return fallback
    }

    static func escapeLLDBString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func makeBreakpointCommand(from breakpoint: DebugBreakpoint) -> String {
        let filePath = breakpoint.filePath.replacingOccurrences(of: "\"", with: "\\\"")
        var command = "breakpoint set --file \"\(filePath)\" --line \(breakpoint.line)"
        if let condition = breakpoint.condition, !condition.isEmpty {
            let escapedCondition = condition.replacingOccurrences(of: "\"", with: "\\\"")
            command += " --condition \"\(escapedCondition)\""
        }
        return command
    }

    static func defaultBatchRunner(commands: [String]) async -> LLDBDAPDebugAdapter.LLDBBatchExecutionResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["lldb", "--batch"] + commands.flatMap { ["-o", $0] }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(
                    returning: .init(
                        exitCode: 1,
                        output: "Impossibile avviare LLDB: \(error.localizedDescription)"
                    )
                )
                return
            }

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                let joined = [out, err]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                continuation.resume(
                    returning: .init(
                        exitCode: proc.terminationStatus,
                        output: joined
                    )
                )
            }
        }
    }

    static func parseBacktrace(from text: String) -> [NativeCallStackFrame] {
        var frames: [NativeCallStackFrame] = []
        let pattern = #"frame #\d+: .*`([^`]+)`.* at ([^:]+):(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return frames }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let function = nsText.substring(with: match.range(at: 1))
            let file = nsText.substring(with: match.range(at: 2))
            let line = Int(nsText.substring(with: match.range(at: 3))) ?? 0
            frames.append(NativeCallStackFrame(function: function, filePath: file, line: line))
        }
        return frames
    }

    static func parseWatchValues(from text: String, expressions: [String]) -> [NativeWatchVariable] {
        guard !expressions.isEmpty else { return [] }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return expressions.map { expression in
            let value = parseWatchValue(for: expression, from: lines) ?? "n/a"
            return NativeWatchVariable(expression: expression, value: value)
        }
    }

    private static func parseWatchValue(for expression: String, from lines: [String]) -> String? {
        let lowercasedExpression = expression.lowercased()
        guard let commandIndex = lines.lastIndex(where: {
            let lowercased = $0.lowercased()
            return lowercased.contains("expression --") && lowercased.contains(lowercasedExpression)
        }) else {
            return nil
        }

        for line in lines.dropFirst(commandIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("(lldb)") {
                break
            }
            return trimmed
        }
        return nil
    }
}
