import Foundation

extension CodexUsageFetcher {
    private struct CodexRateWindow {
        let usedPercent: Double?
        let resetLabel: String?
    }

    static func fetchViaAppServer(
        codexPath: String,
        workingDirectory: String?,
        environmentOverride: [String: String]?
    ) async -> CodexUsage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.standardInput = inPipe
        process.environment = mergedEnvironment(environmentOverride)
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

    static func parseAppServerLine(_ line: String) -> CodexUsage? {
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
        let credits = parseCredits(result: result, snapshot: snapshot)
        return CodexUsage(
            fiveHourPct: primary.usedPercent,
            weeklyPct: secondary.usedPercent,
            resetFiveH: primary.resetLabel,
            resetWeekly: secondary.resetLabel,
            creditsBalance: credits.balance,
            creditsCurrency: credits.currency,
            creditsSource: credits.source
        )
    }

    static func extractSnapshot(_ result: [String: Any]) -> [String: Any] {
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

    static func formatReset(epochSeconds: Double?) -> String? {
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

    static func parseCredits(result: [String: Any], snapshot: [String: Any]) -> (balance: Double?, currency: String?, source: String?) {
        let candidateDicts: [[String: Any]] = [
            result,
            snapshot,
            result["account"] as? [String: Any],
            result["billing"] as? [String: Any],
            result["credits"] as? [String: Any]
        ].compactMap { $0 }

        let balanceKeys = ["creditsBalance", "creditBalance", "balance", "remainingCredits", "remaining_balance", "remaining"]
        let currencyKeys = ["creditsCurrency", "currency", "balanceCurrency"]

        for dict in candidateDicts {
            let balance = number(forKeys: balanceKeys, in: dict)
            if let balance {
                let currency = string(forKeys: currencyKeys, in: dict) ?? "USD"
                return (balance, currency, "app-server")
            }
        }
        return (nil, nil, nil)
    }

    static func number(forKeys keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let n = (dict[key] as? NSNumber)?.doubleValue {
                return n
            }
            if let s = dict[key] as? String, let n = Double(s.replacingOccurrences(of: ",", with: ".")) {
                return n
            }
        }
        return nil
    }

    static func string(forKeys keys: [String], in dict: [String: Any]) -> String? {
        for key in keys {
            if let v = dict[key] as? String, !v.isEmpty {
                return v
            }
        }
        return nil
    }
}
