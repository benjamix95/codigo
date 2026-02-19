import Foundation

public struct GeminiCLIUsage: Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let note: String?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil, note: String? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.note = note
    }
}

public enum GeminiCLIUsageFetcher {
    public static func fetch(geminiPath: String, workingDirectory: String? = nil) async -> GeminiCLIUsage? {
        let command = await runGeminiStats(geminiPath: geminiPath, workingDirectory: workingDirectory)
        guard !command.output.isEmpty else { return nil }
        if let parsed = parseGeminiJSON(command.output) {
            return parsed
        }
        if command.exitCode != 0 {
            return GeminiCLIUsage(note: "Gemini CLI non autenticato o non disponibile")
        }
        return nil
    }

    private static func runGeminiStats(geminiPath: String, workingDirectory: String?) async -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: geminiPath)
        process.arguments = ["-p", "/stats", "--output-format", "json"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.standardInput = nil
        process.environment = CodexDetector.shellEnvironment()
        process.currentDirectoryURL = (workingDirectory.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }).flatMap {
            URL(fileURLWithPath: $0)
        } ?? URL(fileURLWithPath: NSHomeDirectory())

        do {
            try process.run()
            let outputData = try outPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return (String(data: outputData, encoding: .utf8) ?? "", process.terminationStatus)
        } catch {
            return ("", -1)
        }
    }

    private static func parseGeminiJSON(_ text: String) -> GeminiCLIUsage? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return GeminiCLIUsage(note: message)
            }

            if let usage = json["usage"] as? [String: Any] {
                let input = (usage["input_tokens"] as? NSNumber)?.intValue
                let output = (usage["output_tokens"] as? NSNumber)?.intValue
                let total = (usage["total_tokens"] as? NSNumber)?.intValue
                return GeminiCLIUsage(inputTokens: input, outputTokens: output, totalTokens: total)
            }
        }
        return nil
    }
}
