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
    private static let cacheLock = NSLock()
    private static var cliAvailableCache: [String: (result: Bool, date: Date)] = [:]
    private static var authStatusCache: [String: (result: Bool?, date: Date)] = [:]
    private static let cacheTTL: TimeInterval = 60
    private static let authStatusTTL: TimeInterval = 15

    private static var claudeHome: String {
        ProcessInfo.processInfo.environment["CLAUDE_HOME"] ?? "\(NSHomeDirectory())/.claude"
    }

    private static var credentialsPaths: [String] {
        [
            "\(claudeHome)/.credentials.json",
            "\(claudeHome)/credentials.json",
            "\(claudeHome)/auth-status.json",
            "\(NSHomeDirectory())/.claude.json",
        ]
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

    /// Verifica se il file credenziali Claude esiste e contiene credenziali valide
    public static func hasAuthFile() -> Bool {
        for path in credentialsPaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if hasTokenLikeFields(in: json) {
                return true
            }
            if let oauth = json["claudeAiOauth"] as? [String: Any],
               hasTokenLikeFields(in: oauth) {
                return true
            }
            if json["loggedIn"] as? Bool == true {
                return true
            }
        }
        return false
    }

    /// Esegue `claude --version` e ritorna true se il CLI è funzionante.
    /// Usa cache (60s) per evitare blocchi ripetuti del main thread.
    public static func checkCLIAvailable(claudePath: String) -> Bool {
        cacheLock.lock()
        if let cached = cliAvailableCache[claudePath], Date().timeIntervalSince(cached.date) < cacheTTL {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
        process.standardOutput = nil
        process.standardError = nil
        process.environment = shellEnvironment()
        do {
            try process.run()
            let result = waitForExit(process, timeout: 5) == 0
            cacheLock.lock()
            defer { cacheLock.unlock() }
            // Double-check: se un altro thread ha già scritto, non sovrascrivere
            if cliAvailableCache[claudePath] == nil {
                cliAvailableCache[claudePath] = (result, Date())
            }
            return result
        } catch {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            if cliAvailableCache[claudePath] == nil {
                cliAvailableCache[claudePath] = (false, Date())
            }
            return false
        }
    }

    /// Esegue `claude auth status` (con timeout + cache) per validare login reale.
    public static func checkAuthStatus(claudePath: String) -> Bool? {
        cacheLock.lock()
        if let cached = authStatusCache[claudePath], Date().timeIntervalSince(cached.date) < authStatusTTL {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["auth", "status"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.environment = shellEnvironment()

        let result: Bool?
        do {
            try process.run()
            if let exitCode = waitForExit(process, timeout: 8) {
                result = (exitCode == 0)
            } else {
                result = nil
            }
        } catch {
            result = nil
        }

        cacheLock.lock()
        defer { cacheLock.unlock() }
        // Double-check: se un altro thread ha già scritto, non sovrascrivere
        if authStatusCache[claudePath] == nil {
            authStatusCache[claudePath] = (result, Date())
        }
        return result
    }

    /// Detects complete Claude Code CLI status
    public static func detect(customPath: String? = nil) -> ClaudeStatus {
        guard let path = findClaudePath(customPath: customPath) else {
            return ClaudeStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
        }
        let hasAuth = hasAuthFile()
        let cliOk = checkCLIAvailable(claudePath: path)
        let hasEnvKey = shellEnvironment()["ANTHROPIC_API_KEY"] != nil
        let authStatus = cliOk ? checkAuthStatus(claudePath: path) : nil

        let loggedIn: Bool
        if hasEnvKey {
            loggedIn = true
        } else if let authStatus {
            // Authoritative when command succeeds/fails explicitly.
            loggedIn = authStatus
        } else {
            // Fallback only when auth-status could not be determined (timeout/crash).
            loggedIn = hasAuth
        }

        let authMethod: String?
        if loggedIn {
            if hasAuth { authMethod = "file" }
            else if hasEnvKey { authMethod = "env" }
            else if authStatus == true { authMethod = "oauth" }
            else { authMethod = nil }
        } else {
            authMethod = nil
        }
        return ClaudeStatus(
            isInstalled: cliOk, path: path, isLoggedIn: loggedIn, authMethod: authMethod)
    }

    // MARK: - Private

    private static func hasTokenLikeFields(in json: [String: Any]) -> Bool {
        if let value = json["accessToken"] as? String, !value.isEmpty { return true }
        if let value = json["access_token"] as? String, !value.isEmpty { return true }
        if let value = json["token"] as? String, !value.isEmpty { return true }
        if let value = json["oauthToken"] as? String, !value.isEmpty { return true }
        if let value = json["refreshToken"] as? String, !value.isEmpty { return true }
        if let value = json["refresh_token"] as? String, !value.isEmpty { return true }
        return false
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
