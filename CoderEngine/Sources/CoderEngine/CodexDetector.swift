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
        return json["access_token"] != nil || json["token"] != nil
    }

    /// Esegue `codex login status` e ritorna true se loggato
    public static func checkLoginStatus(codexPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "status"]
        process.standardOutput = nil
        process.standardError = nil
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
        let loggedIn = hasAuth || loginOk
        let authMethod = loggedIn ? (hasAuth ? "file" : "keyring") : nil
        return CodexStatus(isInstalled: true, path: path, isLoggedIn: loggedIn, authMethod: authMethod)
    }
}
