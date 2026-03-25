import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "PostgresInstaller")

/// Gestisce la presenza e l'installazione automatica di PostgreSQL via Homebrew.
/// Secondo anello della catena: Homebrew → PostgreSQL → pgvector.
public enum PostgresInstaller {

    /// Versione preferita di PostgreSQL da installare.
    /// Usata quando nessuna versione è già presente.
    static let preferredVersion = "17"

    /// Verifica se PostgreSQL è installato e accessibile.
    public static func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/postgres")
    }

    /// Rileva la major version di PostgreSQL attiva.
    public static func activeMajorVersion() -> String? {
        PgVectorInstaller.detectActiveMajorVersion()
    }

    /// Installa PostgreSQL se non presente. Ritorna true se disponibile dopo la chiamata.
    ///
    /// Richiede Homebrew installato — usa `HomebrewInstaller.ensureInstalled()` prima.
    @discardableResult
    public static func ensureInstalled() -> Bool {
        if isInstalled() {
            logger.info("PostgreSQL already installed (version \(activeMajorVersion() ?? "unknown"))")
            return true
        }

        guard HomebrewInstaller.isInstalled() else {
            logger.error("Homebrew not available — cannot install PostgreSQL")
            return false
        }

        logger.info("PostgreSQL not found — installing postgresql@\(preferredVersion) via Homebrew")

        let success = brewInstallPostgres()
        if success {
            // Homebrew non sempre crea il symlink in /opt/homebrew/bin.
            // `brew link` assicura che i binary siano accessibili.
            brewLinkPostgres()
        }

        if isInstalled() {
            logger.info("PostgreSQL installed successfully (version \(activeMajorVersion() ?? preferredVersion))")
            return true
        }

        logger.error("PostgreSQL installation failed")
        return false
    }

    // MARK: - Private

    private static func brewInstallPostgres() -> Bool {
        runBrew(arguments: ["install", "postgresql@\(preferredVersion)"])
    }

    private static func brewLinkPostgres() {
        // --overwrite per gestire symlink residui da versioni precedenti.
        _ = runBrew(arguments: ["link", "--overwrite", "postgresql@\(preferredVersion)"])
    }

    private static func runBrew(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HomebrewInstaller.brewPath)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

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
                logger.error("brew \(arguments.joined(separator: " ")) failed (exit \(process.terminationStatus)): \(output.prefix(500))")
                return false
            }
            return true
        } catch {
            logger.error("Failed to run brew: \(error.localizedDescription)")
            return false
        }
    }
}
