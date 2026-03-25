import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "PgVectorInstaller")

// MARK: - PgVectorInstaller

/// Ensures pgvector is installed in the Homebrew PostgreSQL installation.
/// Called automatically during bootstrap — the user never needs to install manually.
public enum PgVectorInstaller {

    /// Check if pgvector extension is loadable by the **active** PostgreSQL version.
    ///
    /// Rileva dinamicamente la major version di pg in uso (via `postgres --version`)
    /// e verifica che `vector.control` esista nella directory estensioni corrispondente.
    public static func isInstalled() -> Bool {
        // Controlla SOLO la versione attiva di PostgreSQL.
        // Non fare fallback ad altre versioni: trovare pgvector per pg@17
        // quando il runtime usa pg@14 è un falso positivo.
        guard let extensionDir = activeExtensionDirectory() else {
            logger.warning("Cannot detect active PostgreSQL extension directory — assuming pgvector not available")
            return false
        }
        let controlPath = (extensionDir as NSString).appendingPathComponent("vector.control")
        return FileManager.default.fileExists(atPath: controlPath)
    }

    /// Install pgvector for the active PostgreSQL version if not already present.
    /// Returns true if pgvector is available after this call.
    ///
    /// Strategia:
    /// 1. `brew install pgvector` (copre le versioni supportate da Homebrew)
    /// 2. Se dopo brew la versione attiva non ha pgvector, compila dai sorgenti
    ///    usando `pg_config` della versione attiva.
    @discardableResult
    public static func ensureInstalled() -> Bool {
        if isInstalled() {
            logger.info("pgvector already installed for active PostgreSQL")
            return true
        }

        logger.info("pgvector not found for active PostgreSQL — attempting install")

        // Catena di dipendenze: Homebrew → PostgreSQL → pgvector
        guard HomebrewInstaller.ensureInstalled() else {
            logger.error("Cannot install pgvector — Homebrew installation failed")
            return false
        }

        guard PostgresInstaller.ensureInstalled() else {
            logger.error("Cannot install pgvector — PostgreSQL installation failed")
            return false
        }

        // Step 1: brew install (potrebbe coprire la versione attiva).
        runBrewInstall()
        if isInstalled() {
            logger.info("pgvector installed via Homebrew for active PostgreSQL")
            return true
        }

        // Step 2: la versione attiva non è coperta da Homebrew (es. pg@14).
        // Compila pgvector dai sorgenti.
        logger.info("Homebrew pgvector does not cover active PostgreSQL — building from source")
        let builtFromSource = buildFromSource()
        if builtFromSource && isInstalled() {
            logger.info("pgvector built from source for active PostgreSQL")
            return true
        }

        logger.error("pgvector installation failed for active PostgreSQL")
        return false
    }

    // MARK: - Version Detection

    /// Rileva la major version di PostgreSQL attiva da `/opt/homebrew/bin/postgres --version`.
    static func detectActiveMajorVersion() -> String? {
        let binaryPath = "/opt/homebrew/bin/postgres"
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Formato: "postgres (PostgreSQL) 14.20 (Homebrew)"
        let pattern = #"(\d+)\.\d+"#
        guard let range = output.range(of: pattern, options: .regularExpression),
              let dotIndex = output[range].firstIndex(of: ".") else {
            return nil
        }
        return String(output[range.lowerBound..<dotIndex])
    }

    /// Ritorna la directory delle estensioni per la versione attiva di PostgreSQL.
    static func activeExtensionDirectory() -> String? {
        guard let major = detectActiveMajorVersion() else { return nil }
        let versionedPath = "/opt/homebrew/share/postgresql@\(major)/extension"
        if FileManager.default.fileExists(atPath: versionedPath) {
            return versionedPath
        }
        let genericPath = "/opt/homebrew/share/postgresql/extension"
        if FileManager.default.fileExists(atPath: genericPath) {
            return genericPath
        }
        return nil
    }

    /// Ritorna il path di `pg_config` per la versione attiva.
    private static func activePgConfigPath() -> String? {
        guard let major = detectActiveMajorVersion() else { return nil }
        let versionedPath = "/opt/homebrew/opt/postgresql@\(major)/bin/pg_config"
        if FileManager.default.isExecutableFile(atPath: versionedPath) {
            return versionedPath
        }
        let genericPath = "/opt/homebrew/bin/pg_config"
        if FileManager.default.isExecutableFile(atPath: genericPath) {
            return genericPath
        }
        return nil
    }

    // MARK: - Private

    @discardableResult
    private static func runBrewInstall() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HomebrewInstaller.brewPath)
        process.arguments = ["install", "pgvector"]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("Failed to run brew: \(error.localizedDescription)")
            return false
        }
    }

    /// Compila pgvector dai sorgenti GitHub usando pg_config della versione attiva.
    ///
    /// Passi:
    /// 1. Clona il repo pgvector in una directory temporanea
    /// 2. Esegue `make PG_CONFIG=<path> && make PG_CONFIG=<path> install`
    /// 3. Pulisce la directory temporanea
    private static func buildFromSource() -> Bool {
        guard let pgConfig = activePgConfigPath() else {
            logger.error("pg_config not found for active PostgreSQL — cannot build pgvector from source")
            return false
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pgvector-build-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Clone
        guard runShell(
            "/usr/bin/git",
            arguments: ["clone", "--depth", "1", "--branch", "v0.8.0",
                        "https://github.com/pgvector/pgvector.git", tempDir.path]
        ) else {
            logger.error("Failed to clone pgvector repository")
            return false
        }

        // Make
        var env = ProcessInfo.processInfo.environment
        env["PG_CONFIG"] = pgConfig

        guard runShell(
            "/usr/bin/make",
            arguments: ["-C", tempDir.path, "PG_CONFIG=\(pgConfig)"],
            environment: env
        ) else {
            logger.error("Failed to build pgvector from source")
            return false
        }

        // Make install
        guard runShell(
            "/usr/bin/make",
            arguments: ["-C", tempDir.path, "PG_CONFIG=\(pgConfig)", "install"],
            environment: env
        ) else {
            logger.error("Failed to install pgvector from source")
            return false
        }

        return true
    }

    private static func runShell(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }

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
                logger.error("\(executable) failed (exit \(process.terminationStatus)): \(output.prefix(500))")
            }
            return process.terminationStatus == 0
        } catch {
            logger.error("Failed to run \(executable): \(error.localizedDescription)")
            return false
        }
    }
}
