import Foundation

public struct GeminiCLIUsage: Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let note: String?
    public let sessionCost: String?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        note: String? = nil,
        sessionCost: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.note = note
        self.sessionCost = sessionCost
    }
}

public enum GeminiCLIUsageFetcher {

    // MARK: - Public

    public static func fetch(geminiPath: String, workingDirectory: String? = nil) async
        -> GeminiCLIUsage?
    {
        // 1. Verify Gemini CLI is installed and reachable via --version (fast, never hangs)
        let versionOk = await checkVersion(geminiPath: geminiPath)
        guard versionOk else {
            return GeminiCLIUsage(note: "Gemini CLI non raggiungibile")
        }

        // 2. Try to read usage from local history files (~/.gemini/history/)
        if let historyUsage = readUsageFromHistory(workingDirectory: workingDirectory) {
            return historyUsage
        }

        // Gemini CLI does not expose usage/rate-limit info via CLI commands.
        // Return a placeholder so the UI knows the CLI is connected.
        return GeminiCLIUsage(
            note: "Gemini CLI connesso — usage dettagliato non disponibile via CLI")
    }

    // MARK: - Version health-check

    private static func checkVersion(geminiPath: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: geminiPath)
        process.arguments = ["--version"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.standardInput = nil
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        do {
            try process.run()

            // Read with a tight timeout — --version should return instantly
            let result: Bool = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    do {
                        _ = try outPipe.fileHandleForReading.readToEnd()
                    } catch {}
                    process.waitUntilExit()
                    return process.terminationStatus == 0
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)  // 4s timeout
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                if process.isRunning { process.terminate() }
                return first
            }
            return result
        } catch {
            return false
        }
    }

    // MARK: - Local history parsing

    /// Attempt to read token usage from Gemini CLI's local session history files.
    /// Gemini CLI stores session data as JSON in ~/.gemini/history/<project>/
    private static func readUsageFromHistory(workingDirectory: String?) -> GeminiCLIUsage? {
        let historyBase = (NSHomeDirectory() as NSString).appendingPathComponent(".gemini/history")
        let fm = FileManager.default

        guard fm.fileExists(atPath: historyBase) else { return nil }

        // Collect candidate session directories (project-specific or all)
        var sessionDirs: [String] = []

        // If we know the working directory, try to find its project hash
        if let wd = workingDirectory, !wd.isEmpty {
            // Gemini uses the folder name or a hash as subdirectory
            let folderName = (wd as NSString).lastPathComponent
            let candidate = (historyBase as NSString).appendingPathComponent(folderName)
            if fm.fileExists(atPath: candidate) {
                sessionDirs.append(candidate)
            }
        }

        // Also scan all history subdirectories for the most recent session
        if let entries = try? fm.contentsOfDirectory(atPath: historyBase) {
            for entry in entries where !entry.hasPrefix(".") {
                let full = (historyBase as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    if !sessionDirs.contains(full) {
                        sessionDirs.append(full)
                    }
                }
            }
        }

        // Find the most recent session JSON and try to extract usage
        var bestDate: Date = .distantPast
        var bestUsage: GeminiCLIUsage?

        for dir in sessionDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".json") {
                let filePath = (dir as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                    let modified = attrs[.modificationDate] as? Date
                else { continue }

                // Only consider files from the last 24 hours
                guard Date().timeIntervalSince(modified) < 86400 else { continue }

                if modified > bestDate {
                    if let usage = parseSessionFile(at: filePath) {
                        bestDate = modified
                        bestUsage = usage
                    }
                }
            }
        }

        return bestUsage
    }

    /// Parse a single Gemini CLI session JSON file looking for usage metadata.
    private static func parseSessionFile(at path: String) -> GeminiCLIUsage? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }

        // Session files can be a JSON object or newline-delimited JSON
        // Try as a single JSON object first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return extractUsageFromJSON(json)
        }

        // Try as newline-delimited JSON (last line often has summary)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines).reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                let lineData = trimmed.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let usage = extractUsageFromJSON(json) {
                return usage
            }
        }
        return nil
    }

    /// Extract usage fields from a JSON dictionary (handles various Gemini formats)
    private static func extractUsageFromJSON(_ json: [String: Any]) -> GeminiCLIUsage? {
        // Direct usage object
        if let usage = json["usage"] as? [String: Any] {
            return usageFromDict(usage)
        }

        // Nested in usageMetadata (Google AI format)
        if let meta = json["usageMetadata"] as? [String: Any] {
            let input = (meta["promptTokenCount"] as? NSNumber)?.intValue
            let output = (meta["candidatesTokenCount"] as? NSNumber)?.intValue
            let total = (meta["totalTokenCount"] as? NSNumber)?.intValue
            if input != nil || output != nil || total != nil {
                return GeminiCLIUsage(inputTokens: input, outputTokens: output, totalTokens: total)
            }
        }

        // Look inside response candidates
        if let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let meta = first["usageMetadata"] as? [String: Any]
        {
            return usageFromDict(meta)
        }

        // Nested in modelResponse
        if let modelResponse = json["modelResponse"] as? [String: Any] {
            return extractUsageFromJSON(modelResponse)
        }

        // Check for error info
        if let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return GeminiCLIUsage(note: message)
        }

        return nil
    }

    private static func usageFromDict(_ dict: [String: Any]) -> GeminiCLIUsage? {
        let inputKeys = ["input_tokens", "promptTokenCount", "prompt_tokens"]
        let outputKeys = ["output_tokens", "candidatesTokenCount", "completion_tokens"]
        let totalKeys = ["total_tokens", "totalTokenCount"]

        let input = numberForKeys(inputKeys, in: dict)
        let output = numberForKeys(outputKeys, in: dict)
        let total = numberForKeys(totalKeys, in: dict)

        guard input != nil || output != nil || total != nil else { return nil }
        return GeminiCLIUsage(inputTokens: input, outputTokens: output, totalTokens: total)
    }

    private static func numberForKeys(_ keys: [String], in dict: [String: Any]) -> Int? {
        for key in keys {
            if let n = (dict[key] as? NSNumber)?.intValue {
                return n
            }
        }
        return nil
    }
}
