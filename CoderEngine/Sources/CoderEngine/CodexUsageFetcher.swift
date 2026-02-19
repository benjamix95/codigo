import Foundation

/// Usage Codex: 5h rolling e settimanale
public struct CodexUsage: Sendable {
    public let fiveHourPct: Double?
    public let weeklyPct: Double?
    public let resetFiveH: String?
    public let resetWeekly: String?

    public init(fiveHourPct: Double? = nil, weeklyPct: Double? = nil, resetFiveH: String? = nil, resetWeekly: String? = nil) {
        self.fiveHourPct = fiveHourPct
        self.weeklyPct = weeklyPct
        self.resetFiveH = resetFiveH
        self.resetWeekly = resetWeekly
    }
}

private struct CodexRateWindow {
    let usedPercent: Double?
    let resetLabel: String?
}

/// Recupera usage da Codex CLI.
/// Strategia:
/// 1) app-server JSON-RPC account/rateLimits/read (affidabile)
/// 2) fallback best-effort su `/status` (legacy)
public enum CodexUsageFetcher {
    public static func fetch(codexPath: String, workingDirectory: String? = nil) async -> CodexUsage? {
        if let usage = await fetchViaAppServer(codexPath: codexPath, workingDirectory: workingDirectory) {
            return usage
        }
        let (output, status) = await runCodexStatus(codexPath: codexPath, workingDirectory: workingDirectory)
        guard status == 0, !output.isEmpty else { return nil }
        return parseStatusOutput(output)
    }

    private static func fetchViaAppServer(codexPath: String, workingDirectory: String?) async -> CodexUsage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.standardInput = inPipe
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL = workingDirectory.flatMap {
            FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil
        } ?? URL(fileURLWithPath: NSHomeDirectory())

        do {
            try process.run()
            let inputWriter = Task.detached(priority: .userInitiated) {
                let initRequest =
                    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codigo","version":"1.0"},"protocolVersion":"2025-06-18","capabilities":{}}}"# + "\n"
                inPipe.fileHandleForWriting.write(Data(initRequest.utf8))
                // app-server può ignorare richieste successive se inviate tutte insieme.
                try? await Task.sleep(nanoseconds: 120_000_000)
                let postInitRequests = [
                    #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
                    #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#
                ].joined(separator: "\n") + "\n"
                inPipe.fileHandleForWriting.write(Data(postInitRequests.utf8))
            }
            let usage = await withTaskGroup(of: CodexUsage?.self) { group in
                group.addTask {
                    do {
                        for try await line in outPipe.fileHandleForReading.bytes.lines {
                            if let parsed = parseAppServerLine(line) {
                                return parsed
                            }
                        }
                    } catch {
                        return nil
                    }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }

            inputWriter.cancel()
            try? inPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            return usage
        } catch {
            return nil
        }
    }

    private static func parseAppServerLine(_ line: String) -> CodexUsage? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int,
              id == 2,
              let result = json["result"] as? [String: Any] else {
            return nil
        }

        let snapshot = extractSnapshot(result)
        let primary = parseRateWindow(from: snapshot["primary"] as? [String: Any])
        let secondary = parseRateWindow(from: snapshot["secondary"] as? [String: Any])
        return CodexUsage(
            fiveHourPct: primary.usedPercent,
            weeklyPct: secondary.usedPercent,
            resetFiveH: primary.resetLabel,
            resetWeekly: secondary.resetLabel
        )
    }

    private static func extractSnapshot(_ result: [String: Any]) -> [String: Any] {
        if let byLimit = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byLimit["codex"] as? [String: Any] {
            return codex
        }
        return (result["rateLimits"] as? [String: Any]) ?? result
    }

    private static func parseRateWindow(from payload: [String: Any]?) -> CodexRateWindow {
        guard let payload else { return .init(usedPercent: nil, resetLabel: nil) }
        let used = (payload["usedPercent"] as? NSNumber)?.doubleValue
        let resetEpoch = (payload["resetsAt"] as? NSNumber)?.doubleValue
        return .init(usedPercent: used, resetLabel: formatReset(epochSeconds: resetEpoch))
    }

    private static func formatReset(epochSeconds: Double?) -> String? {
        guard let epochSeconds else { return nil }
        let date = Date(timeIntervalSince1970: epochSeconds)
        let now = Date()
        let calendar = Calendar.current

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }

    private static func runCodexStatus(codexPath: String, workingDirectory: String?) async -> (output: String, exitCode: Int32) {
        var args = ["exec", "--json", "--skip-git-repo-check"]
        if let wd = workingDirectory, !wd.isEmpty, FileManager.default.fileExists(atPath: wd) {
            args = ["exec", "--json", "-C", wd]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = args
        process.standardInput = Pipe()
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL = workingDirectory.flatMap { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/tmp")
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

    private static func parseStatusOutput(_ text: String) -> CodexUsage {
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

    private static func extractPercentFromJsonLine(_ line: String) -> Double? {
        guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var text = ""
        if let item = json["item"] as? [String: Any], let content = item["content"] as? [[String: Any]] {
            text = content.compactMap { $0["text"] as? String }.joined()
        } else if let t = (json["text"] as? String) ?? ((json["delta"] as? [String: Any])?["text"] as? String) { text = t }
        return text.isEmpty ? nil : extractPercent(from: text)
    }

    private static func extractPercent(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }
}
