import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "RipgrepInstaller")

// MARK: - RipgrepInstaller

/// Assicura che il binario **ripgrep** (`rg`) sia disponibile sul Mac host.
/// Usato da tool di ricerca (Swift + MCP Rust) quando `rg` è nel PATH o sotto Homebrew.
/// Catena: **Homebrew → `brew install ripgrep`** (se `rg` assente).
public enum RipgrepInstaller {

    /// Percorsi tipici su macOS (Apple Silicon e Intel Homebrew).
    public static let commonBinaryPaths: [String] = [
        "/opt/homebrew/bin/rg",
        "/usr/local/bin/rg",
    ]

    /// True se esiste un eseguibile `rg` nei path noti o in PATH (`/usr/bin/env rg` non serve; controlliamo file).
    public static func isInstalled() -> Bool {
        for path in commonBinaryPaths where FileManager.default.isExecutableFile(atPath: path) {
            return true
        }
        if let whichPath = pathFromWhichRg(), FileManager.default.isExecutableFile(atPath: whichPath) {
            return true
        }
        return false
    }

    /// Installa ripgrep via Homebrew se mancante. Best-effort (non blocca l’app se fallisce).
    @discardableResult
    public static func ensureInstalled() -> Bool {
        if isInstalled() {
            logger.debug("ripgrep (rg) già disponibile")
            return true
        }
        guard HomebrewInstaller.ensureInstalled() else {
            logger.error("Impossibile installare ripgrep — Homebrew non disponibile")
            return false
        }
        logger.info("ripgrep non trovato — installazione con brew install ripgrep")
        guard brewInstallRipgrep() else {
            logger.error("brew install ripgrep fallito")
            return false
        }
        if isInstalled() {
            logger.info("ripgrep installato correttamente")
            return true
        }
        logger.warning("brew install ripgrep completato ma rg non trovato nei path attesi")
        return false
    }

    // MARK: - Private

    private static func pathFromWhichRg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["rg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return out.isEmpty ? nil : out
        } catch {
            return nil
        }
    }

    private static func brewInstallRipgrep() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HomebrewInstaller.brewPath)
        process.arguments = ["install", "ripgrep"]
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                logger.error("brew install ripgrep exit \(process.terminationStatus): \(output.prefix(400))")
                return false
            }
            return true
        } catch {
            logger.error("brew install ripgrep: \(error.localizedDescription)")
            return false
        }
    }
}
