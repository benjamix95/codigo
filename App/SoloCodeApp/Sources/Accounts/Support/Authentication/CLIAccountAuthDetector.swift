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

struct CLIAccountIdentity: Equatable {
    let email: String?
    let displayName: String?
    let accountId: String?
    let authMethod: CLIAccountAuthMethod?
}

enum CLIAccountAuthDetector {
    static func detect(account: CLIAccount, providerPath: String?) -> CLIAccountAuthStatus {
        let executable = resolveExecutable(provider: account.provider, providerPath: providerPath)
        guard let executable else { return .notInstalled }
        guard FileManager.default.isExecutableFile(atPath: executable) else { return .notInstalled }

        let fallback = profileBasedStatus(account: account)

        if Thread.isMainThread {
            // Never block the UI thread on Process.waitUntilExit(). SwiftUI can
            // pump the run loop during graph construction and crash AttributeGraph.
            return fallback
        }

        let env = buildEnvironment(for: account)
        do {
            let ok = try runLoginStatus(provider: account.provider, executable: executable, environment: env)
            if ok {
                if case .loggedIn(let method) = fallback {
                    return .loggedIn(method: method)
                }
                return .loggedIn(method: .oauth)
            }
            if account.provider == .claude {
                return .notLoggedIn
            }
            return fallback
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    static func detectOffMainThread(account: CLIAccount, providerPath: String?) async -> CLIAccountAuthStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let status = detect(account: account, providerPath: providerPath)
                continuation.resume(returning: status)
            }
        }
    }

    static func identity(account: CLIAccount) -> CLIAccountIdentity? {
        switch account.provider {
        case .codex:
            return codexIdentity(account: account)
        case .claude:
            return claudeIdentity(account: account)
        case .gemini:
            return genericIdentityFromFile(
                account: account,
                fileCandidates: ["auth.json", "credentials.json", "config.json"]
            )
        }
    }

    static func resolveExecutable(provider: CLIProviderKind, providerPath: String?) -> String? {
        if let providerPath, !providerPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: providerPath) {
            return providerPath
        }
        switch provider {
        case .codex:
            return CodexDetector.findCodexPath(customPath: nil)
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

    static func stringValue(_ dict: [String: Any]?, keys: [String]) -> String? {
        guard let dict else { return nil }
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func extractEmailFromJWTPayload(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let email = stringValue(raw, keys: ["email"]) {
            return email
        }

        if let profile = raw["https://api.openai.com/profile"] as? [String: Any],
           let profileEmail = stringValue(profile, keys: ["email"]) {
            return profileEmail
        }
        return nil
    }

    static func hasEnvironmentCredential(account: CLIAccount) -> Bool {
        let env = buildEnvironment(for: account)
        switch account.provider {
        case .codex:
            let key = env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !key.isEmpty
        case .claude:
            let key = env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !key.isEmpty
        case .gemini:
            let gemini = env["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let google = env["GOOGLE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !gemini.isEmpty || !google.isEmpty
        }
    }
}
