import Foundation
import AppKit
import CoderEngine

/// Actor that encapsulates all Process-execution and polling logic for Codex login.
/// Keeps the SwiftUI view free from process management details.
actor CodexLoginService {

    enum LoginResult: Sendable {
        case success
        case failure(String)
        case timeout
    }

    // MARK: - API Key Login

    /// Runs `codex login --with-api-key`, piping the key via stdin.
    static func loginWithAPIKey(codexPath: String, apiKey: String) async -> LoginResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "--with-api-key"]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = nil
        process.standardError = nil
        process.environment = CodexDetector.shellEnvironment()

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((apiKey + "\n").data(using: .utf8) ?? Data())
            try inputPipe.fileHandleForWriting.close()
        } catch {
            return .failure("Failed to launch codex process.")
        }

        let status = await waitForTermination(process)
        guard status == 0 else {
            return .failure("Login failed. Verify API key and try again.")
        }

        let loggedIn = await pollForCompletion(codexPath: codexPath)
        return loggedIn ? .success : .timeout
    }

    // MARK: - Browser / Device-Code Login

    /// Runs `codex login` with optional extra args (e.g. `["--device-auth"]`).
    /// Detects URLs in stdout and opens them in the system browser on the main thread.
    static func runBrowserLogin(codexPath: String, args: [String]) async -> LoginResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login"] + args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.environment = CodexDetector.shellEnvironment()

        do {
            try process.run()
        } catch {
            return .failure("Failed to launch codex process.")
        }

        // Read output asynchronously — open login URLs in the system browser
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if let regex = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text),
               let url = URL(string: String(text[range])) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }

        let status = await waitForTermination(process)
        outPipe.fileHandleForReading.readabilityHandler = nil

        guard status == 0 else {
            return .failure("Login not completed. Try again.")
        }

        let loggedIn = await pollForCompletion(codexPath: codexPath)
        return loggedIn ? .success : .timeout
    }

    // MARK: - Polling

    /// Polls `CodexDetector.detect` until `isLoggedIn` returns true or max attempts exhausted.
    static func pollForCompletion(
        codexPath: String,
        maxAttempts: Int = 30,
        intervalSeconds: Int = 2
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .seconds(intervalSeconds))
            let ready = await Task.detached {
                CodexDetector.detect(customPath: codexPath).isLoggedIn
            }.value
            if ready { return true }
        }
        return false
    }

    // MARK: - Helpers

    /// Bridges the callback-based `terminationHandler` into async/await.
    private static func waitForTermination(_ process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }
    }
}
