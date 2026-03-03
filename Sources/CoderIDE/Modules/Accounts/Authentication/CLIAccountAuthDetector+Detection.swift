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
        process.waitUntilExit()
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
}
