import Foundation

extension CodexUsageFetcher {
    static func runCodexStatus(
        codexPath: String,
        workingDirectory: String?,
        environmentOverride: [String: String]?
    ) async -> (output: String, exitCode: Int32) {
        var args = ["exec", "--json", "--skip-git-repo-check"]
        if let wd = workingDirectory, !wd.isEmpty, FileManager.default.fileExists(atPath: wd) {
            args += ["-C", wd]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = args
        process.standardInput = Pipe()
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.environment = mergedEnvironment(environmentOverride)
        process.currentDirectoryURL = workingDirectory
            .flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
            ?? URL(fileURLWithPath: "/tmp")
        let stdin = "/status\n"
        do {
            try process.run()
            if let inputPipe = process.standardInput as? Pipe {
                inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }
            var output = ""
            for try await byte in outPipe.fileHandleForReading.bytes {
                if let c = String(bytes: [byte], encoding: .utf8) { output += c }
            }
            process.waitUntilExit()
            return (output, process.terminationStatus)
        } catch {
            return ("", -1)
        }
    }

    static func parseStatusOutput(_ text: String) -> CodexUsage {
        var fivePct: Double?
        var weekPct: Double?
        var reset5: String?
        var resetWeek: String?

        for line in text.components(separatedBy: .newlines) {
            if let pct = extractPercentFromJsonLine(line) { if fivePct == nil { fivePct = pct }; continue }
            let lower = line.lowercased()
            if lower.contains("5 h") || lower.contains("5h") || lower.contains("5-hour") {
                if let pct = extractPercent(from: line) { fivePct = pct }
            }
            if lower.contains("settimana") || lower.contains("week") || lower.contains("weekly") {
                if let pct = extractPercent(from: line) { weekPct = pct }
            }
            if lower.contains("ripristino") || lower.contains("reset") {
                let rest = line.replacingOccurrences(of: #"\d+\s*h\s*:\s*"#, with: "", options: .regularExpression)
                if let t = rest.trimmingCharacters(in: .whitespaces).components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces), !t.isEmpty { reset5 = t; resetWeek = t }
            }
        }
        if fivePct == nil, weekPct == nil, let pct = extractPercent(from: text) { fivePct = pct }
        return CodexUsage(fiveHourPct: fivePct, weeklyPct: weekPct, resetFiveH: reset5, resetWeekly: resetWeek)
    }

    static func extractPercentFromJsonLine(_ line: String) -> Double? {
        guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var text = ""
        if let item = json["item"] as? [String: Any], let content = item["content"] as? [[String: Any]] {
            text = content.compactMap { $0["text"] as? String }.joined()
        } else if let t = (json["text"] as? String) ?? ((json["delta"] as? [String: Any])?["text"] as? String) { text = t }
        return text.isEmpty ? nil : extractPercent(from: text)
    }

    static func extractPercent(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    static func mergedEnvironment(_ override: [String: String]?) -> [String: String] {
        var env = CodexDetector.shellEnvironment()
        if let override {
            env.merge(override) { _, new in new }
        }
        return env
    }
}
