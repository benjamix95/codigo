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
        if let rustLog = env["RUST_LOG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           rustLog.isEmpty {
            env["RUST_LOG"] = "error"
        } else if env["RUST_LOG"] == nil {
            env["RUST_LOG"] = "error"
        }

        return env
    }

    /// Rileva path di Codex CLI
    public static func findCodexPath(customPath: String? = nil) -> String? {
        if let custom = customPath, !custom.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: custom) else {
                return nil
            }
            return custom
        }
        return preferredCodexPath(
            candidates: codexPathCandidates(),
            allowsBlockingVersionProbe: !Thread.isMainThread
        )
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

    /// Detects complete Codex status
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

    static func preferredCodexPath(
        candidates: [String],
        versionLoader: (String) -> String? = loadCodexVersion,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        allowsBlockingVersionProbe: Bool = true
    ) -> String? {
        let uniqueCandidates = Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates

        struct RankedCandidate {
            let path: String
            let version: CodexSemanticVersion?
        }

        let ranked = uniqueCandidates.compactMap { rawPath -> RankedCandidate? in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, isExecutable(path) else { return nil }
            return RankedCandidate(
                path: path,
                version: allowsBlockingVersionProbe
                    ? versionLoader(path).flatMap(CodexSemanticVersion.parse)
                    : nil
            )
        }

        guard !ranked.isEmpty else { return nil }
        if !allowsBlockingVersionProbe {
            return ranked.first?.path
        }

        let stableCandidates = ranked.filter { version in
            guard let version = version.version else { return false }
            return !version.isPrerelease
        }
        if let bestStable = stableCandidates.max(by: { lhs, rhs in
            guard let left = lhs.version, let right = rhs.version else { return false }
            return left < right
        }) {
            return bestStable.path
        }

        if let bestKnown = ranked.compactMap({ candidate -> RankedCandidate? in
            guard candidate.version != nil else { return nil }
            return candidate
        }).max(by: { lhs, rhs in
            guard let left = lhs.version, let right = rhs.version else { return false }
            return left < right
        }) {
            return bestKnown.path
        }

        return ranked.first?.path
    }

    private static func codexPathCandidates() -> [String] {
        var candidates: [String] = []
        if let discovered = PathFinder.find(executable: "codex") {
            candidates.append(discovered)
        }

        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.yarn/bin/codex",
            "\(home)/.bun/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ])

        return candidates
    }

    private static func loadCodexVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = nil
        process.environment = shellEnvironment()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

private struct CodexSemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    var isPrerelease: Bool { prerelease?.isEmpty == false }

    static func parse(_ raw: String) -> CodexSemanticVersion? {
        let pattern = /([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([A-Za-z0-9.\-]+))?/
        guard let match = raw.firstMatch(of: pattern),
              let major = Int(match.output.1),
              let minor = Int(match.output.2),
              let patch = Int(match.output.3)
        else {
            return nil
        }
        let prerelease = match.output.4.map(String.init)
        return CodexSemanticVersion(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease
        )
    }

    static func < (lhs: CodexSemanticVersion, rhs: CodexSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (left?, right?):
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}
