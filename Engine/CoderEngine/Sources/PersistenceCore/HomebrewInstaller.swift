import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "HomebrewInstaller")

/// Gestisce la presenza e l'installazione automatica di Homebrew.
/// Usato come primo anello della catena: Homebrew → PostgreSQL → pgvector.
public enum HomebrewInstaller {

    /// Path standard di Homebrew su Apple Silicon.
    static let brewPath = "/opt/homebrew/bin/brew"

    /// Verifica se Homebrew è installato e accessibile.
    public static func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: brewPath)
    }

    /// Installa Homebrew se non presente. Ritorna true se disponibile dopo la chiamata.
    @discardableResult
    public static func ensureInstalled() -> Bool {
        if isInstalled() {
            logger.info("Homebrew already installed")
            return true
        }

        logger.info("Homebrew not found — installing automatically")

        let success = runInstallScript()
        if success && isInstalled() {
            logger.info("Homebrew installed successfully")
            return true
        }

        logger.error("Homebrew installation failed")
        return false
    }

    // MARK: - Private

    /// Esegue lo script ufficiale di installazione Homebrew in modalità non-interattiva.
    private static func runInstallScript() -> Bool {
        // Lo script ufficiale Homebrew supporta NONINTERACTIVE=1 per CI/automazione.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["NONINTERACTIVE"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let output = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                logger.error("Homebrew install script failed (exit \(process.terminationStatus)): \(output.prefix(500))")
                return false
            }
            return true
        } catch {
            logger.error("Failed to run Homebrew install script: \(error.localizedDescription)")
            return false
        }
    }
}
