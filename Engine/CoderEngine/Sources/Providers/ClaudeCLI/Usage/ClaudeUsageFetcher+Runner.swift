import Foundation

extension ClaudeUsageFetcher {
    static func runClaudeCost(
        claudePath: String,
        workingDirectory: String?,
        environmentOverride: [String: String]?
    ) async -> ClaudeCommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        // NOTE: We do NOT pass --no-session-persistence so that /cost reads
        // the accumulated session data instead of a fresh empty session.
        process.arguments = ["-p", "--verbose", "--output-format", "stream-json", "/cost"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = nil
        process.standardInput = nil
        process.environment = mergedEnvironment(environmentOverride)
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

    static func mergedEnvironment(_ override: [String: String]?) -> [String: String] {
        var env = ClaudeDetector.shellEnvironment()
        if let override {
            env.merge(override) { _, new in new }
        }
        return env
    }
}
