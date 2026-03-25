import Foundation

/// Stato rilevato di Kilo CLI
public struct KiloStatus: Sendable {
    public let isInstalled: Bool
    public let path: String?
    public let hasCredentials: Bool

    public init(isInstalled: Bool, path: String?, hasCredentials: Bool) {
        self.isInstalled = isInstalled
        self.path = path
        self.hasCredentials = hasCredentials
    }
}

/// Rileva installazione e stato auth di Kilo CLI
public enum KiloDetector {
    private static let cacheLock = NSLock()
    private static var cliCache: [String: (result: Bool, date: Date)] = [:]
    private static let cacheTTL: TimeInterval = 60

    /// Rileva path di Kilo CLI
    public static func findKiloPath(customPath: String? = nil) -> String? {
        if let custom = customPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        return PathFinder.find(executable: "kilo")
    }

    /// Verifica se il CLI è funzionante via `kilo --version`
    public static func checkCLIAvailable(kiloPath: String) -> Bool {
        cacheLock.lock()
        if let cached = cliCache[kiloPath],
           Date().timeIntervalSince(cached.date) < cacheTTL {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kiloPath)
        process.arguments = ["--version"]
        process.standardOutput = nil
        process.standardError = nil
        process.environment = CodexDetector.shellEnvironment()
        let result: Bool
        do {
            try process.run()
            process.waitUntilExit()
            result = process.terminationStatus == 0
        } catch {
            result = false
        }

        cacheLock.lock()
        defer { cacheLock.unlock() }
        // Double-check: se un altro thread ha già scritto durante l'operazione, non sovrascrivere
        if cliCache[kiloPath] == nil {
            cliCache[kiloPath] = (result, Date())
        }
        return result
    }

    /// Verifica se Kilo ha credenziali configurate
    public static func hasCredentials() -> Bool {
        let authPath = "\(NSHomeDirectory())/.local/share/kilo/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        // auth.json contiene credenziali se ha almeno un provider
        if let providers = json["providers"] as? [Any], !providers.isEmpty {
            return true
        }
        if json.keys.contains(where: { $0.contains("token") || $0.contains("key") }) {
            return true
        }
        return false
    }

    /// Detects complete Kilo CLI status
    public static func detect(customPath: String? = nil) -> KiloStatus {
        guard let path = findKiloPath(customPath: customPath) else {
            return KiloStatus(isInstalled: false, path: nil, hasCredentials: false)
        }
        let cliOk = checkCLIAvailable(kiloPath: path)
        let hasCreds = hasCredentials()
        return KiloStatus(isInstalled: cliOk, path: path, hasCredentials: hasCreds)
    }
}
