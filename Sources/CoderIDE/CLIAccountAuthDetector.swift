import Foundation
import CoderEngine

enum CLIAccountAuthMethod: String, Codable, Equatable {
    case oauth
    case device
    case apiKey
    case file
}

enum CLIAccountAuthStatus: Equatable {
    case notInstalled
    case notLoggedIn
    case loggedIn(method: CLIAccountAuthMethod)
    case error(message: String)

    var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }
}

enum CLIAccountAuthDetector {
    static func detect(account: CLIAccount, providerPath: String?) -> CLIAccountAuthStatus {
        let executable = resolveExecutable(provider: account.provider, providerPath: providerPath)
        guard let executable else { return .notInstalled }
        guard FileManager.default.isExecutableFile(atPath: executable) else { return .notInstalled }

        // Non bloccare mai il main thread (render SwiftUI): evita waitUntilExit in UI pass.
        // In UI path evitiamo anche falsi positivi basati su stato storico non verificato.
        if Thread.isMainThread {
            if let secret = CLIAccountSecretsStore().secret(for: account.id), !secret.isEmpty {
                return .loggedIn(method: .apiKey)
            }
            return .notLoggedIn
        }

        let env = buildEnvironment(for: account)
        do {
            let ok = try runLoginStatus(provider: account.provider, executable: executable, environment: env)
            if ok {
                if let secret = CLIAccountSecretsStore().secret(for: account.id), !secret.isEmpty {
                    return .loggedIn(method: .apiKey)
                }
                return .loggedIn(method: .oauth)
            }
            if let secret = CLIAccountSecretsStore().secret(for: account.id), !secret.isEmpty {
                return .loggedIn(method: .apiKey)
            }
            return .notLoggedIn
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    static func resolveExecutable(provider: CLIProviderKind, providerPath: String?) -> String? {
        if let providerPath, !providerPath.isEmpty {
            return providerPath
        }
        switch provider {
        case .codex:
            return CodexDetector.findCodexPath(customPath: nil) ?? PathFinder.find(executable: "codex")
        case .claude:
            return PathFinder.find(executable: "claude")
        case .gemini:
            return GeminiDetector.findGeminiPath(customPath: providerPath)
        }
    }

    static func buildEnvironment(for account: CLIAccount) -> [String: String] {
        let secret = CLIAccountSecretsStore().secret(for: account.id)
        var env = CodexDetector.shellEnvironment()
        let overrides = CLIProfileProvisioner.environmentOverrides(
            provider: account.provider,
            profilePath: account.profilePath,
            secret: secret
        )
        env.merge(overrides) { _, new in new }
        return env
    }

    private static func runLoginStatus(provider: CLIProviderKind, executable: String, environment: [String: String]) throws -> Bool {
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
}
