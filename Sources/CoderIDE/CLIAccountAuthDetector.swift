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

        // Never block the main thread in SwiftUI render paths.
        // Use profile/keychain artifacts for a fast status.
        if Thread.isMainThread {
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

    private static func profileBasedStatus(account: CLIAccount) -> CLIAccountAuthStatus {
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

    private static func codexIdentity(account: CLIAccount) -> CLIAccountIdentity? {
        let authPath = URL(fileURLWithPath: account.profilePath, isDirectory: true)
            .appendingPathComponent("auth.json").path
        guard let data = FileManager.default.contents(atPath: authPath),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let apiKey = (raw["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = raw["tokens"] as? [String: Any]

        var email = stringValue(raw, keys: ["email"])
        if email == nil {
            email = stringValue(tokens, keys: ["email"])
        }
        if email == nil,
           let idToken = tokens?["id_token"] as? String {
            email = extractEmailFromJWTPayload(idToken)
        }
        if email == nil,
           let accessToken = tokens?["access_token"] as? String {
            email = extractEmailFromJWTPayload(accessToken)
        }

        let accountId = stringValue(tokens, keys: ["account_id", "accountId"])
            ?? stringValue(raw, keys: ["account_id", "accountId"])

        let method: CLIAccountAuthMethod?
        if let apiKey, !apiKey.isEmpty {
            method = .apiKey
        } else if tokens != nil {
            method = .oauth
        } else {
            method = .file
        }

        return CLIAccountIdentity(email: email, displayName: nil, accountId: accountId, authMethod: method)
    }

    private static func claudeIdentity(account: CLIAccount) -> CLIAccountIdentity? {
        let base = URL(fileURLWithPath: account.profilePath, isDirectory: true)
        let candidates = [
            ".claude.json",
            ".claude/.credentials.json",
            ".claude/credentials.json",
            ".credentials.json",
            "credentials.json",
            ".claude/auth-status.json",
            "auth-status.json",
        ]

        for candidate in candidates {
            let path = base.appendingPathComponent(candidate).path
            guard let data = FileManager.default.contents(atPath: path),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let dicts = identityLookupDictionaries(root: raw)
            let email = dicts.lazy.compactMap {
                stringValue($0, keys: ["email", "user_email", "account_email", "emailAddress"])
            }.first
            let displayName = dicts.lazy.compactMap {
                stringValue($0, keys: ["displayName", "name", "fullName", "username"])
            }.first
            let accountId = dicts.lazy.compactMap {
                stringValue(
                    $0,
                    keys: [
                        "orgId", "org_id", "organizationUuid",
                        "account_id", "accountId", "accountUuid",
                        "user_id", "userId"
                    ]
                )
            }.first

            let hasOAuthTokens = dicts.contains { dict in
                stringValue(dict, keys: ["accessToken", "access_token", "refreshToken", "refresh_token", "oauthToken", "token"]) != nil
            }
            let loggedInFlag = raw["loggedIn"] as? Bool == true

            if hasOAuthTokens || loggedInFlag || email != nil || accountId != nil || displayName != nil {
                return CLIAccountIdentity(email: email, displayName: displayName, accountId: accountId, authMethod: .oauth)
            }
        }
        return nil
    }

    private static func genericIdentityFromFile(account: CLIAccount, fileCandidates: [String]) -> CLIAccountIdentity? {
        let base = URL(fileURLWithPath: account.profilePath, isDirectory: true)
        for candidate in fileCandidates {
            let path = base.appendingPathComponent(candidate).path
            guard let data = FileManager.default.contents(atPath: path),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let email = stringValue(raw, keys: ["email", "user_email", "account_email"])
            let accountId = stringValue(raw, keys: ["account_id", "accountId", "user_id", "userId"])
            if email != nil || accountId != nil {
                return CLIAccountIdentity(email: email, displayName: nil, accountId: accountId, authMethod: .oauth)
            }
            return CLIAccountIdentity(email: nil, displayName: nil, accountId: nil, authMethod: .file)
        }
        return nil
    }

    private static func identityLookupDictionaries(root: [String: Any]) -> [[String: Any]] {
        var result: [[String: Any]] = [root]
        let nestedKeys = ["auth", "oauth", "user", "account", "profile", "claudeAiOauth", "oauthAccount"]
        for key in nestedKeys {
            if let nested = root[key] as? [String: Any] {
                result.append(nested)
            }
        }
        return result
    }

    private static func stringValue(_ dict: [String: Any]?, keys: [String]) -> String? {
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

    private static func extractEmailFromJWTPayload(_ token: String) -> String? {
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

    private static func hasEnvironmentCredential(account: CLIAccount) -> Bool {
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
