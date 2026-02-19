import Foundation

/// Usage Claude Code: costo sessione / token
public struct ClaudeUsage: Sendable {
    public let sessionCost: String?
    public let inputTokens: Int?
    public let outputTokens: Int?

    public init(sessionCost: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.sessionCost = sessionCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

private struct ClaudeCommandOutput {
    let output: String
    let exitCode: Int32
}

/// Recupera usage da Claude Code CLI tramite stream JSON strutturato.
public enum ClaudeUsageFetcher {
    public static func fetch(claudePath: String, workingDirectory: String? = nil) async -> ClaudeUsage? {
        let command = await runClaudeCost(claudePath: claudePath, workingDirectory: workingDirectory)
        guard command.exitCode == 0, !command.output.isEmpty else { return nil }
        if let usage = parseStreamJSON(command.output) {
            return usage
        }
        return parseCostOutput(command.output)
    }

    private static func runClaudeCost(claudePath: String, workingDirectory: String?) async -> ClaudeCommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", "--no-session-persistence", "--verbose", "--output-format", "stream-json", "/cost"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.standardInput = nil
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL = (workingDirectory.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }).flatMap { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        do {
            try process.run()
            var output = ""
            for try await byte in outPipe.fileHandleForReading.bytes {
                if let c = String(bytes: [byte], encoding: .utf8) { output += c }
            }
            process.waitUntilExit()
            return ClaudeCommandOutput(output: output, exitCode: process.terminationStatus)
        } catch {
            return ClaudeCommandOutput(output: "", exitCode: -1)
        }
    }

    private static func parseStreamJSON(_ text: String) -> ClaudeUsage? {
        var sessionCost: String?
        var inputTokens: Int?
        var outputTokens: Int?

        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            guard type == "result" else { continue }
            let result = json["result"] as? [String: Any]

            if let cost = json["total_cost_usd"] as? NSNumber {
                sessionCost = String(format: "$%.4f", cost.doubleValue)
            }
            if let usage = json["usage"] as? [String: Any] {
                if let inp = usage["input_tokens"] as? NSNumber { inputTokens = inp.intValue }
                if let out = usage["output_tokens"] as? NSNumber { outputTokens = out.intValue }
            }
            if let embeddedUsage = result?["usage"] as? [String: Any] {
                if inputTokens == nil, let inp = embeddedUsage["input_tokens"] as? NSNumber { inputTokens = inp.intValue }
                if outputTokens == nil, let out = embeddedUsage["output_tokens"] as? NSNumber { outputTokens = out.intValue }
            }
            if sessionCost == nil, let embeddedCost = result?["total_cost_usd"] as? NSNumber {
                sessionCost = String(format: "$%.4f", embeddedCost.doubleValue)
            }
        }

        if sessionCost == nil, inputTokens == nil, outputTokens == nil {
            return nil
        }
        return ClaudeUsage(sessionCost: sessionCost, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    private static func parseCostOutput(_ text: String) -> ClaudeUsage {
        var cost: String?
        var inTokens: Int?
        var outTokens: Int?
        let lower = text.lowercased()
        if lower.contains("total cost") || lower.contains("$") {
            let pattern = #"\$\s*[\d.]+"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
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
