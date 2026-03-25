import Darwin
import Foundation

public final class ManagedPostgresService {
    public static let shared = ManagedPostgresService()

    private let configurationOverride: ManagedPostgresConfiguration?
    private let queue = DispatchQueue(label: "CoderEngine.Persistence.ManagedPostgres")
    private var cachedHealth: PersistenceHealthSnapshot?
    private var isBootstrapped = false

    public init(configuration: ManagedPostgresConfiguration? = nil) {
        self.configurationOverride = configuration
    }

    public func bootstrapIfNeeded() throws -> PersistenceHealthSnapshot {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        return try queue.sync {
            // Fast path: se già bootstrappato, ritorna il risultato cachato.
            if isBootstrapped, let cached = cachedHealth {
                return cached
            }

            let configuration = resolvedConfiguration()
            try validateBinaries()
            try PersistenceSupport.ensureDirectory(configuration.rootDirectory)
            try PersistenceSupport.ensureDirectory(configuration.socketDirectory)

            // Lock file cross-processo per evitare che due processi facciano initdb in parallelo.
            let lockFilePath = configuration.rootDirectory.appendingPathComponent(".bootstrap.lock").path
            let lockFd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
            if lockFd >= 0 {
                if !Self.flockWithTimeout(lockFd, timeout: 15) {
                    close(lockFd)
                    throw PersistenceBootstrapError.bootstrapFailed(
                        "Timeout acquiring bootstrap lock after 15s — another process may hold it"
                    )
                }
            }
            defer {
                if lockFd >= 0 {
                    flock(lockFd, LOCK_UN)
                    close(lockFd)
                }
            }

            // Ricontrolla PG_VERSION sotto lock per evitare TOCTOU.
            let pgVersionPath = configuration.dataDirectory.appendingPathComponent("PG_VERSION").path
            if !FileManager.default.fileExists(atPath: pgVersionPath) {
                try PersistenceSupport.ensureDirectory(configuration.dataDirectory.deletingLastPathComponent())
                _ = try runProcess(
                    executable: configuration.initdbBinary,
                    arguments: [
                        "-D", configuration.dataDirectory.path,
                        "-A", "trust",
                        "-U", configuration.userName,
                        "-E", "UTF8",
                    ]
                )
            }

            if !isHealthy(databaseName: "postgres") {
                let postgresOptions = [
                    "-k", shellQuoted(configuration.socketDirectory.path),
                    "-p", String(configuration.port),
                ].joined(separator: " ")
                _ = try runProcess(
                    executable: configuration.pgCtlBinary,
                    arguments: [
                        "-D", configuration.dataDirectory.path,
                        "-l", configuration.logFile.path,
                        "-o", postgresOptions,
                        "start",
                    ]
                )
            }

            guard isHealthy(databaseName: "postgres") else {
                throw PersistenceBootstrapError.healthCheckFailed("Unable to connect to bootstrap database.")
            }
            try ensureDatabaseExists()

            let health = PersistenceHealthSnapshot(
                isReady: true,
                databaseName: configuration.databaseName,
                host: configuration.socketDirectory.path,
                port: configuration.port,
                dataDirectoryPath: configuration.dataDirectory.path,
                socketDirectoryPath: configuration.socketDirectory.path,
                schemaVersion: 0,
                importedLegacyData: false,
                lastMigrationAt: nil,
                lastImportAt: nil,
                lastError: nil
            )
            cachedHealth = health
            isBootstrapped = true
            return health
        }
    }

    // MARK: - Database Size & Cleanup

    /// Returns the total size of the Postgres data directory in bytes.
    public func dataDirSizeBytes() -> UInt64 {
        let configuration = resolvedConfiguration()
        let dataPath = configuration.dataDirectory.path
        guard FileManager.default.fileExists(atPath: dataPath) else { return 0 }
        let enumerator = FileManager.default.enumerator(
            at: configuration.dataDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var total: UInt64 = 0
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    /// Stops Postgres and removes the entire data directory.
    public func deleteDatabase() throws {
        try shutdownIfRunning()
        let configuration = resolvedConfiguration()
        let root = configuration.rootDirectory
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    public func shutdownIfRunning() throws {
        queue.sync {
            let configuration = resolvedConfiguration()
            guard FileManager.default.fileExists(atPath: configuration.dataDirectory.path) else { return }
            _ = try? runProcess(
                executable: configuration.pgCtlBinary,
                arguments: ["-D", configuration.dataDirectory.path, "stop", "-m", "fast"]
            )
            cachedHealth = nil
            isBootstrapped = false
        }
    }

    public func connectionInfo() throws -> ManagedPostgresConnectionInfo {
        let configuration = resolvedConfiguration()
        _ = try bootstrapIfNeeded()
        return ManagedPostgresConnectionInfo(
            databaseName: configuration.databaseName,
            userName: configuration.userName,
            host: configuration.socketDirectory.path,
            port: configuration.port
        )
    }

    private func validateBinaries() throws {
        let configuration = resolvedConfiguration()
        for binary in [
            configuration.initdbBinary,
            configuration.pgCtlBinary,
            configuration.createdbBinary,
            configuration.psqlBinary,
        ] where !FileManager.default.isExecutableFile(atPath: binary) {
            throw PersistenceBootstrapError.binaryMissing(binary)
        }
    }

    private func ensureDatabaseExists() throws {
        let configuration = resolvedConfiguration()
        if isHealthy(databaseName: configuration.databaseName) {
            return
        }
        _ = try? runPSQL(databaseName: "postgres", sql: "SELECT 1;")
        do {
            _ = try runProcess(
                executable: configuration.createdbBinary,
                arguments: [
                    "-h", configuration.socketDirectory.path,
                    "-p", String(configuration.port),
                    "-U", configuration.userName,
                    configuration.databaseName,
                ]
            )
        } catch {
            if !isHealthy(databaseName: configuration.databaseName) {
                throw PersistenceBootstrapError.databaseCreationFailed(error.localizedDescription)
            }
        }
    }

    func runPSQL(databaseName: String, sql: String) throws -> String {
        let configuration = resolvedConfiguration()
        let tempURL = configuration.rootDirectory.appendingPathComponent("\(UUID().uuidString).sql")
        try sql.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try runProcess(
            executable: configuration.psqlBinary,
            arguments: [
                "-X",
                "-qAt",
                "-v", "ON_ERROR_STOP=1",
                "-h", configuration.socketDirectory.path,
                "-p", String(configuration.port),
                "-U", configuration.userName,
                "-d", databaseName,
                "-f", tempURL.path,
            ]
        )
    }

    private func isHealthy(databaseName: String) -> Bool {
        (try? runPSQL(databaseName: databaseName, sql: "SELECT 1;").trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let result = try ProcessSupervisor.runCollectingSync(
            executable: executable,
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            timeout: 30
        )
        guard result.terminationStatus == 0 else {
            throw PersistenceBootstrapError.bootstrapFailed(
                result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.stdout
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func resolvedConfiguration() -> ManagedPostgresConfiguration {
        configurationOverride ?? .default
    }

    /// Non-blocking flock con retry e timeout. Previene deadlock se un altro processo
    /// muore tenendo il lock.
    static func flockWithTimeout(_ fd: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let result = flock(fd, LOCK_EX | LOCK_NB)
            if result == 0 { return true }
            let err = errno
            if err != EWOULDBLOCK && err != EAGAIN { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}
