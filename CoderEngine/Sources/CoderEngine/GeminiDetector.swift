import Foundation

/// Stato rilevato di Gemini CLI
public struct GeminiStatus: Sendable {
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

/// Rileva installazione e stato auth di Gemini CLI
public enum GeminiDetector {
    /// Builds an environment dict that includes PATH (con percorsi npm/nvm/fnm/volta) e GEMINI/GOOGLE API keys
    public static func shellEnvironment() -> [String: String] {
        var env = CodexDetector.shellEnvironment()
        let home = NSHomeDirectory()
        var extraPath: [String] = []
        extraPath.append("\(home)/.npm/bin")
        extraPath.append("\(home)/.npm-global/bin")
        extraPath.append("\(home)/.local/bin")
        extraPath.append("\(home)/.volta/bin")
        extraPath.append("/usr/local/lib/node_modules/.bin")
        if let nvmDir = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            for verDir in nvmDir.sorted().reversed() {
                extraPath.append("\(home)/.nvm/versions/node/\(verDir)/bin")
            }
        }
        if let fnmDir = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.fnm/node-versions") {
            for verDir in fnmDir.sorted().reversed() {
                extraPath.append("\(home)/.fnm/node-versions/\(verDir)/installation/bin")
            }
        }
        if let fnmLocal = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.local/share/fnm/node-versions") {
            for verDir in fnmLocal.sorted().reversed() {
                extraPath.append("\(home)/.local/share/fnm/node-versions/\(verDir)/installation/bin")
            }
        }
        let path = env["PATH"] ?? ""
        let added = extraPath.filter { !path.contains($0) }.joined(separator: ":")
        if !added.isEmpty {
            env["PATH"] = "\(added):\(path)"
        }
        if env["GEMINI_API_KEY"] == nil, env["GOOGLE_API_KEY"] == nil,
           let key = loadGeminiApiKeyFromShellConfig() {
            env["GEMINI_API_KEY"] = key
        }
        return env
    }

    /// Rileva path di Gemini CLI (Homebrew, npm global, nvm, fnm, volta, PATH)
    public static func findGeminiPath(customPath: String? = nil) -> String? {
        if let custom = customPath, !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let env = shellEnvironment()
        let pathEnv = env["PATH"] ?? ""
        let paths = pathEnv.split(separator: ":").map(String.init)
        for dir in paths {
            let fullPath = "\(dir)/gemini"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        for defaultPath in ["/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"] {
            if FileManager.default.isExecutableFile(atPath: defaultPath) {
                return defaultPath
            }
        }
        // Percorsi tipici quando installato con npm install -g gemini-cli
        let home = NSHomeDirectory()
        let npmPaths = [
            "\(home)/.npm/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "/usr/local/lib/node_modules/.bin",
        ]
        for dir in npmPaths {
            let fullPath = "\(dir)/gemini"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        // nvm: ~/.nvm/versions/node/*/bin
        if let nvmDir = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            for verDir in nvmDir.sorted().reversed() {
                let binPath = "\(home)/.nvm/versions/node/\(verDir)/bin/gemini"
                if FileManager.default.isExecutableFile(atPath: binPath) {
                    return binPath
                }
            }
        }
        // fnm: ~/.local/share/fnm/node-versions/*/installation/bin
        if let fnmDir = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.local/share/fnm/node-versions") {
            for verDir in fnmDir.sorted().reversed() {
                let binPath = "\(home)/.local/share/fnm/node-versions/\(verDir)/installation/bin/gemini"
                if FileManager.default.isExecutableFile(atPath: binPath) {
                    return binPath
                }
            }
        }
        // fnm su macOS: ~/.fnm/node-versions
        if let fnmDir = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.fnm/node-versions") {
            for verDir in fnmDir.sorted().reversed() {
                let binPath = "\(home)/.fnm/node-versions/\(verDir)/installation/bin/gemini"
                if FileManager.default.isExecutableFile(atPath: binPath) {
                    return binPath
                }
            }
        }
        // Volta: ~/.volta/bin
        let voltaPath = "\(home)/.volta/bin/gemini"
        if FileManager.default.isExecutableFile(atPath: voltaPath) {
            return voltaPath
        }
        return nil
    }

    /// Verifica se GEMINI_API_KEY o GOOGLE_API_KEY sono presenti in env
    public static func hasAuthEnv() -> Bool {
        let env = shellEnvironment()
        return env["GEMINI_API_KEY"] != nil || env["GOOGLE_API_KEY"] != nil
    }

    /// Esegue `gemini --version` e ritorna true se ok (Gemini CLI non ha `auth status`)
    public static func checkAuth(geminiPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: geminiPath)
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

    /// Rileva stato completo di Gemini
    public static func detect(customPath: String? = nil) -> GeminiStatus {
        guard let path = findGeminiPath(customPath: customPath) else {
            return GeminiStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
        }
        let hasEnvKey = hasAuthEnv()
        let checkOk = checkAuth(geminiPath: path)
        let loggedIn = hasEnvKey || checkOk

        let authMethod: String?
        if loggedIn {
            if hasEnvKey { authMethod = "env" }
            else { authMethod = "cached" }
        } else {
            authMethod = nil
        }
        return GeminiStatus(isInstalled: true, path: path, isLoggedIn: loggedIn, authMethod: authMethod)
    }

    // MARK: - Private

    private static func loadGeminiApiKeyFromShellConfig() -> String? {
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
                for prefix in ["export GEMINI_API_KEY=", "GEMINI_API_KEY=", "export GOOGLE_API_KEY=", "GOOGLE_API_KEY="] {
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
        if let envContent = try? String(contentsOfFile: "\(home)/.gemini/.env", encoding: .utf8) {
            for line in envContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                if trimmed.hasPrefix("GEMINI_API_KEY=") || trimmed.hasPrefix("GOOGLE_API_KEY=") {
                    let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        var value = parts[1].trimmingCharacters(in: .whitespaces)
                        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                           (value.hasPrefix("'") && value.hasSuffix("'")) {
                            value = String(value.dropFirst().dropLast())
                        }
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }
}
