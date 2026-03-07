import Foundation

extension CLIAccountAuthDetector {
    static func runLoginStatus(provider: CLIProviderKind, executable: String, environment: [String: String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        switch provider {
        case .codex:
            process.arguments = ["login", "status"]
        case .claude:
            process.arguments = ["auth", "status"]
        case .gemini:
            process.arguments = ["--version"]
        }
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        let timeout: TimeInterval
        switch provider {
        case .claude:
            timeout = 8
        case .codex, .gemini:
            timeout = 5
        }
        guard waitForExit(process, timeout: timeout) != nil else {
            return false
        }
        return process.terminationStatus == 0
    }

    static func profileBasedStatus(account: CLIAccount) -> CLIAccountAuthStatus {
        if let secret = CLIAccountSecretsStore().secret(for: account.id), !secret.isEmpty {
            return .loggedIn(method: .apiKey)
        }
        if hasEnvironmentCredential(account: account) {
            return .loggedIn(method: .apiKey)
        }
        if let identity = identity(account: account),
           let method = identity.authMethod {
            return .loggedIn(method: method)
        }
        return .notLoggedIn
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Int32? {
        let timeoutItem = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + max(0.1, timeout),
            execute: timeoutItem
        )
        process.waitUntilExit()
        timeoutItem.cancel()
        if process.terminationReason == .uncaughtSignal {
            return nil
        }
        return process.terminationStatus
    }
}
