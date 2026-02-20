import Foundation

/// Usage Claude Code: costo sessione / token
public struct ClaudeUsage: Sendable {
    public let sessionCost: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let totalDuration: String?

    public init(
        sessionCost: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        totalDuration: String? = nil
    ) {
        self.sessionCost = sessionCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalDuration = totalDuration
    }
}

private struct ClaudeCommandOutput {
    let output: String
    let exitCode: Int32
}

/// Recupera usage da Claude Code CLI tramite stream JSON strutturato.
public enum ClaudeUsageFetcher {

    // MARK: - Public

    public static func fetch(claudePath: String, workingDirectory: String? = nil) async
        -> ClaudeUsage?
    {
        let command = await runClaudeCost(
            claudePath: claudePath, workingDirectory: workingDirectory)
        guard command.exitCode == 0, !command.output.isEmpty else { return nil }

        // Strategy:
        // 1. Parse the `user` message that contains <local-command-stdout>...</local-command-stdout>
        //    with the REAL accumulated session cost/usage.
        // 2. Fallback: parse the `result` message JSON fields.
        // 3. Fallback: plain text regex parsing.

        if let usage = parseStreamJSON(command.output) {
            return usage
        }
        return parseCostOutput(command.output)
    }

    // MARK: - Run Claude CLI

    private static func runClaudeCost(claudePath: String, workingDirectory: String?) async
        -> ClaudeCommandOutput
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        // NOTE: We do NOT pass --no-session-persistence so that /cost reads
        // the accumulated session data instead of a fresh empty session.
        process.arguments = ["-p", "--verbose", "--output-format", "stream-json", "/cost"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.standardInput = nil
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL =
            (workingDirectory.flatMap {
                FileManager.default.fileExists(atPath: $0) ? $0 : nil
            }).flatMap { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())

        do {
            try process.run()

            // Read with a timeout to avoid hanging if Claude prompts for login
            let result: ClaudeCommandOutput = await withTaskGroup(of: ClaudeCommandOutput.self) {
                group in
                group.addTask {
                    var output = ""
                    do {
                        for try await byte in outPipe.fileHandleForReading.bytes {
                            if let c = String(bytes: [byte], encoding: .utf8) { output += c }
                        }
                    } catch {}
                    process.waitUntilExit()
                    return ClaudeCommandOutput(output: output, exitCode: process.terminationStatus)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)  // 8s timeout
                    return ClaudeCommandOutput(output: "", exitCode: -1)
                }
                let first = await group.next() ?? ClaudeCommandOutput(output: "", exitCode: -1)
                group.cancelAll()
                if process.isRunning { process.terminate() }
                return first
            }
            return result
        } catch {
            return ClaudeCommandOutput(output: "", exitCode: -1)
        }
    }

    // MARK: - Stream JSON parsing

    private static func parseStreamJSON(_ text: String) -> ClaudeUsage? {
        var sessionCost: String?
        var inputTokens: Int?
        var outputTokens: Int?
        var cacheReadTokens: Int?
        var cacheWriteTokens: Int?
        var totalDuration: String?

        for line in text.components(separatedBy: .newlines)
        where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = json["type"] as? String
            else {
                continue
            }

            // === Priority 1: Parse the `user` message with <local-command-stdout> ===
            // This contains the REAL accumulated session cost from Claude Code.
            // Format: {"type":"user","message":{"content":"<local-command-stdout>Total cost: $X.XXXX\n..."}}
            if type == "user" {
                if let message = json["message"] as? [String: Any],
                    let content = message["content"] as? String
                {
                    if let parsed = parseLocalCommandStdout(content) {
                        // This is the most reliable source — use it directly
                        return parsed
                    }
                }
                continue
            }

            // === Priority 2: Parse the `result` message JSON fields ===
            guard type == "result" else { continue }

            let result = json["result"] as? [String: Any]

            // total_cost_usd at top level
            if let cost = json["total_cost_usd"] as? NSNumber {
                let val = cost.doubleValue
                if val > 0 || sessionCost == nil {
                    sessionCost = String(format: "$%.4f", val)
                }
            }

            // usage at top level
            if let usage = json["usage"] as? [String: Any] {
                if let inp = usage["input_tokens"] as? NSNumber { inputTokens = inp.intValue }
                if let out = usage["output_tokens"] as? NSNumber { outputTokens = out.intValue }
                if let cr = usage["cache_read_input_tokens"] as? NSNumber {
                    cacheReadTokens = cr.intValue
                }
                if let cw = usage["cache_creation_input_tokens"] as? NSNumber {
                    cacheWriteTokens = cw.intValue
                }
            }

            // Embedded in result dict
            if let embeddedUsage = result?["usage"] as? [String: Any] {
                if inputTokens == nil, let inp = embeddedUsage["input_tokens"] as? NSNumber {
                    inputTokens = inp.intValue
                }
                if outputTokens == nil, let out = embeddedUsage["output_tokens"] as? NSNumber {
                    outputTokens = out.intValue
                }
            }
            if sessionCost == nil, let embeddedCost = result?["total_cost_usd"] as? NSNumber {
                sessionCost = String(format: "$%.4f", embeddedCost.doubleValue)
            }

            // duration
            if let durMs = json["duration_api_ms"] as? NSNumber {
                let seconds = durMs.doubleValue / 1000.0
                if seconds > 0 {
                    totalDuration = String(format: "%.1fs", seconds)
                }
            }
        }

        if sessionCost == nil, inputTokens == nil, outputTokens == nil {
            return nil
        }
        return ClaudeUsage(
            sessionCost: sessionCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            totalDuration: totalDuration
        )
    }

    // MARK: - Parse <local-command-stdout> content

    /// Parses the text content inside <local-command-stdout>...</local-command-stdout>.
    /// Example content:
    /// ```
    /// Total cost:            $1.2345
    /// Total duration (API):  42s
    /// Total duration (wall): 1m 12s
    /// Total code changes:    15 lines added, 3 lines removed
    /// Usage:                 12345 input, 6789 output, 500 cache read, 200 cache write
    /// ```
    private static func parseLocalCommandStdout(_ content: String) -> ClaudeUsage? {
        // Extract text between <local-command-stdout> and </local-command-stdout>
        let text: String
        if let startRange = content.range(of: "<local-command-stdout>"),
            let endRange = content.range(of: "</local-command-stdout>")
        {
            text = String(content[startRange.upperBound..<endRange.lowerBound])
        } else if content.contains("Total cost") || content.contains("Usage:") {
            text = content
        } else {
            return nil
        }

        var sessionCost: String?
        var inputTokens: Int?
        var outputTokens: Int?
        var cacheReadTokens: Int?
        var cacheWriteTokens: Int?
        var totalDuration: String?

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // "Total cost:            $1.2345"
            if trimmed.lowercased().hasPrefix("total cost") {
                if let dollarRange = trimmed.range(of: "$") {
                    let costStr = String(trimmed[dollarRange.lowerBound...]).trimmingCharacters(
                        in: .whitespaces)
                    // Extract the dollar amount
                    let pattern = #"\$[\d.]+"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                        let match = regex.firstMatch(
                            in: costStr, range: NSRange(costStr.startIndex..., in: costStr)),
                        let range = Range(match.range, in: costStr)
                    {
                        sessionCost = String(costStr[range])
                    }
                }
                continue
            }

            // "Total duration (API):  42s"
            if trimmed.lowercased().hasPrefix("total duration (api)") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let durStr = parts[1...].joined(separator: ":").trimmingCharacters(
                        in: .whitespaces)
                    if durStr != "0s" {
                        totalDuration = durStr
                    }
                }
                continue
            }

            // "Usage:                 12345 input, 6789 output, 500 cache read, 200 cache write"
            if trimmed.lowercased().hasPrefix("usage:") {
                let usagePart = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                let segments = usagePart.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                for segment in segments {
                    let lower = segment.lowercased()
                    if let num = extractLeadingNumber(from: segment) {
                        if lower.contains("cache read") {
                            cacheReadTokens = num
                        } else if lower.contains("cache write") || lower.contains("cache creation")
                        {
                            cacheWriteTokens = num
                        } else if lower.contains("input") || lower.contains("prompt") {
                            inputTokens = num
                        } else if lower.contains("output") || lower.contains("completion") {
                            outputTokens = num
                        }
                    }
                }
                continue
            }
        }

        // Only return if we got something useful
        if sessionCost == nil, inputTokens == nil, outputTokens == nil {
            return nil
        }

        return ClaudeUsage(
            sessionCost: sessionCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            totalDuration: totalDuration
        )
    }

    /// Extract the leading integer from a string like "12345 input"
    private static func extractLeadingNumber(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(\d[\d,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let range = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }
        return Int(trimmed[range].replacingOccurrences(of: ",", with: ""))
    }

    // MARK: - Fallback plain text parsing

    private static func parseCostOutput(_ text: String) -> ClaudeUsage {
        var cost: String?
        var inTokens: Int?
        var outTokens: Int?
        let lower = text.lowercased()

        if lower.contains("total cost") || lower.contains("$") {
            let pattern = #"\$\s*[\d.]+"#
            if let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range, in: text)
            {
                cost = String(text[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        let tokenPattern = #"(\d[\d,]*)\s*(?:input|prompt|token)"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let m = matches.first, let r = Range(m.range(at: 1), in: text) {
                inTokens = Int(text[r].replacingOccurrences(of: ",", with: ""))
            }
        }

        let outPattern = #"(\d[\d,]*)\s*(?:output|completion)"#
        if let regex = try? NSRegularExpression(pattern: outPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let m = matches.first, let r = Range(m.range(at: 1), in: text) {
                outTokens = Int(text[r].replacingOccurrences(of: ",", with: ""))
            }
        }

        return ClaudeUsage(sessionCost: cost, inputTokens: inTokens, outputTokens: outTokens)
    }
}
