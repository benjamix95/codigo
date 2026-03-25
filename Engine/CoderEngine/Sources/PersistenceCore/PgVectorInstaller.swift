import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "PgVectorInstaller")

// MARK: - PgVectorInstaller

/// Ensures pgvector is installed in the Homebrew PostgreSQL installation.
/// Called automatically during bootstrap — the user never needs to install manually.
public enum PgVectorInstaller {

    /// Check if pgvector extension is loadable by PostgreSQL.
    public static func isInstalled() -> Bool {
        // Check for the .so / .dylib in the Homebrew pg extension dir.
        let candidates = [
            "/opt/homebrew/lib/postgresql@17/vector.dylib",
            "/opt/homebrew/lib/postgresql@16/vector.dylib",
            "/opt/homebrew/lib/postgresql/vector.dylib",
            "/opt/homebrew/share/postgresql@17/extension/vector.control",
            "/opt/homebrew/share/postgresql@16/extension/vector.control",
            "/opt/homebrew/share/postgresql/extension/vector.control",
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Install pgvector via Homebrew if not already present.
    /// Returns true if pgvector is available after this call.
    @discardableResult
    public static func ensureInstalled() -> Bool {
        if isInstalled() {
            logger.info("pgvector already installed")
            return true
        }

        logger.info("pgvector not found — attempting auto-install via Homebrew")

        guard isBrewAvailable() else {
            logger.warning("Homebrew not found — cannot auto-install pgvector")
            return false
        }

        let result = runBrewInstall()
        if result {
            logger.info("pgvector installed successfully via Homebrew")
        } else {
            logger.error("pgvector installation failed")
        }
        return result
    }

    // MARK: - Private

    private static func isBrewAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
    }

    private static func runBrewInstall() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["install", "pgvector"]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let exitCode = process.terminationStatus

            if exitCode != 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                logger.error("brew install pgvector failed (exit \(exitCode)): \(output.prefix(500))")
                return false
            }
            return isInstalled()
        } catch {
            logger.error("Failed to run brew: \(error.localizedDescription)")
            return false
        }
    }
}
