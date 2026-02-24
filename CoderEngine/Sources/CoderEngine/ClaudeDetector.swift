import Foundation

/// Stato rilevato di Claude Code CLI
public struct ClaudeStatus: Sendable {
    public let isInstalled: Bool
    public let path: String?
    public let isLoggedIn: Bool
    public let authMethod: String?

    public init(isInstalled: Bool, path: String?, isLoggedIn: Bool, authMethod: String?) {
        self.isInstalled = isInstalled
        self.path = path
        self.isLoggedIn = isLoggedIn
        self.authMethod = authMethod
    }
}

/// Rileva installazione e stato login di Claude Code CLI
public enum ClaudeDetector {
    private static var claudeHome: String {
        ProcessInfo.processInfo.environment["CLAUDE_HOME"] ?? "\(NSHomeDirectory())/.claude"
    }

    private static var credentialsPath: String {
        "\(claudeHome)/credentials.json"
    }

    /// Builds an environment dict that includes PATH and ANTHROPIC_API_KEY from shell config.
    public static func shellEnvironment() -> [String: String] {
        var env = CodexDetector.shellEnvironment()
        if env["ANTHROPIC_API_KEY"] == nil, let key = loadAnthropicKeyFromShellConfig() {
            env["ANTHROPIC_API_KEY"] = key
        }
        return env
    }

    /// Rileva path di Claude Code CLI
    public static func findClaudePath(customPath: String? = nil) -> String? {
        if let custom = customPath, !custom.isEmpty,
            FileManager.default.isExecutableFile(atPath: custom)
        {
            return custom
        }
        return PathFinder.find(executable: "claude")
    }

    /// Verifica se credentials.json esiste e contiene credenziali valide
    public static func hasAuthFile() -> Bool {
        let path = credentialsPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        if json["accessToken"] != nil || json["access_token"] != nil || json["token"] != nil {
            return true
        }
        if let oauthToken = json["oauthToken"] as? String, !oauthToken.isEmpty { return true }
        return false
    }

    /// Esegue `claude --version` e ritorna true se il CLI è funzionante
    public static func checkCLIAvailable(claudePath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
        process.standardOutput = nil
        process.standardError = nil
        process.environment = shellEnvironment()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Rileva stato completo di Claude Code CLI
    public static func detect(customPath: String? = nil) -> ClaudeStatus {
        guard let path = findClaudePath(customPath: customPath) else {
            return ClaudeStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
        }
        let hasAuth = hasAuthFile()
        let cliOk = checkCLIAvailable(claudePath: path)
        let hasEnvKey = shellEnvironment()["ANTHROPIC_API_KEY"] != nil
        let loggedIn = hasAuth || cliOk || hasEnvKey

        let authMethod: String?
        if loggedIn {
            if hasAuth { authMethod = "file" }
            else if hasEnvKey { authMethod = "env" }
            else { authMethod = "cli" }
        } else {
            authMethod = nil
        }
        return ClaudeStatus(
            isInstalled: true, path: path, isLoggedIn: loggedIn, authMethod: authMethod)
    }

    // MARK: - Private

    private static func loadAnthropicKeyFromShellConfig() -> String? {
        let home = NSHomeDirectory()
        let files = [
            "\(home)/.zshenv", "\(home)/.zshrc",
            "\(home)/.bash_profile", "\(home)/.bashrc", "\(home)/.profile",
        ]
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                for prefix in ["export ANTHROPIC_API_KEY=", "ANTHROPIC_API_KEY="] {
                    guard trimmed.hasPrefix(prefix) else { continue }
                    var value = String(trimmed.dropFirst(prefix.count))
                    if (value.hasPrefix("\"") && value.hasSuffix("\""))
                        || (value.hasPrefix("'") && value.hasSuffix("'"))
                    {
                        value = String(value.dropFirst().dropLast())
                    }
                    if !value.isEmpty && !value.hasPrefix("$") { return value }
                }
            }
        }
        return nil
    }
}
