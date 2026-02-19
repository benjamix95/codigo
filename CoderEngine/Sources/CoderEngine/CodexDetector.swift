import Foundation

/// Stato rilevato di Codex CLI
public struct CodexStatus: Sendable {
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

/// Rileva installazione e stato login di Codex CLI
public enum CodexDetector {
    private static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }

    private static var authJsonPath: String {
        "\(codexHome)/auth.json"
    }

    /// Builds an environment dict that includes common binary paths and
    /// OPENAI_API_KEY from shell config files (GUI apps don't inherit shell env).
    public static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        var path = env["PATH"] ?? ""
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            if !path.contains(dir) { path += ":\(dir)" }
        }
        env["PATH"] = path

        if env["OPENAI_API_KEY"] == nil, let key = loadAPIKeyFromShellConfig() {
            env["OPENAI_API_KEY"] = key
        }

        return env
    }

    /// Rileva path di Codex CLI
    public static func findCodexPath(customPath: String? = nil) -> String? {
        if let custom = customPath, !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        return PathFinder.find(executable: "codex")
    }

    /// Verifica se auth.json esiste e contiene credenziali
    public static func hasAuthFile() -> Bool {
        let path = authJsonPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if json["access_token"] != nil || json["token"] != nil { return true }
        if let tokens = json["tokens"] as? [String: Any],
           tokens["access_token"] != nil || tokens["id_token"] != nil { return true }
        return false
    }

    /// Esegue `codex login status` e ritorna true se loggato
    public static func checkLoginStatus(codexPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "status"]
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

    /// Rileva stato completo di Codex
    public static func detect(customPath: String? = nil) -> CodexStatus {
        guard let path = findCodexPath(customPath: customPath) else {
            return CodexStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
        }
        let hasAuth = hasAuthFile()
        let loginOk = checkLoginStatus(codexPath: path)
        let hasEnvKey = shellEnvironment()["OPENAI_API_KEY"] != nil
        let loggedIn = hasAuth || loginOk || hasEnvKey

        let authMethod: String?
        if loggedIn {
            if hasAuth { authMethod = "file" }
            else if loginOk { authMethod = "keyring" }
            else { authMethod = "env" }
        } else {
            authMethod = nil
        }
        return CodexStatus(isInstalled: true, path: path, isLoggedIn: loggedIn, authMethod: authMethod)
    }

    // MARK: - Private

    private static func loadAPIKeyFromShellConfig() -> String? {
        let home = NSHomeDirectory()
        let files = [
            "\(home)/.zshenv", "\(home)/.zshrc",
            "\(home)/.bash_profile", "\(home)/.bashrc", "\(home)/.profile"
        ]
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                for prefix in ["export OPENAI_API_KEY=", "OPENAI_API_KEY="] {
                    guard trimmed.hasPrefix(prefix) else { continue }
                    var value = String(trimmed.dropFirst(prefix.count))
                    if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                       (value.hasPrefix("'") && value.hasSuffix("'")) {
                        value = String(value.dropFirst().dropLast())
                    }
                    if !value.isEmpty && !value.hasPrefix("$") { return value }
                }
            }
        }
        return nil
    }
}
