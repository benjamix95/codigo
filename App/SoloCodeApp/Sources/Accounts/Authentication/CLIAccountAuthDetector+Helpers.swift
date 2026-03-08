import Foundation

extension CLIAccountAuthDetector {
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
