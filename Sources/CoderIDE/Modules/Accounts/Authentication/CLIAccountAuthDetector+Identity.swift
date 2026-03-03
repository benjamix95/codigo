import Foundation

extension CLIAccountAuthDetector {
    static func codexIdentity(account: CLIAccount) -> CLIAccountIdentity? {
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

    static func claudeIdentity(account: CLIAccount) -> CLIAccountIdentity? {
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
            let email = dicts.compactMap({
                stringValue($0, keys: ["email", "user_email", "account_email", "emailAddress"])
            }).first
            let displayName = dicts.compactMap({
                stringValue($0, keys: ["displayName", "name", "fullName", "username"])
            }).first
            let accountId = dicts.compactMap({
                stringValue(
                    $0,
                    keys: [
                        "orgId", "org_id", "organizationUuid",
                        "account_id", "accountId", "accountUuid",
                        "user_id", "userId"
                    ]
                )
            }).first

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

    static func genericIdentityFromFile(account: CLIAccount, fileCandidates: [String]) -> CLIAccountIdentity? {
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

    static func identityLookupDictionaries(root: [String: Any]) -> [[String: Any]] {
        var result: [[String: Any]] = [root]
        let nestedKeys = ["auth", "oauth", "user", "account", "profile", "claudeAiOauth", "oauthAccount"]
        for key in nestedKeys {
            if let nested = root[key] as? [String: Any] {
                result.append(nested)
            }
        }
        return result
    }
}
