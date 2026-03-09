import Foundation

public final class ManagedPostgresService {
    public static let shared = ManagedPostgresService()

    private let configuration: ManagedPostgresConfiguration
    private let queue = DispatchQueue(label: "CoderEngine.Persistence.ManagedPostgres")
    private var cachedHealth: PersistenceHealthSnapshot?

    public init(configuration: ManagedPostgresConfiguration = .default) {
        self.configuration = configuration
    }

    public func bootstrapIfNeeded() throws -> PersistenceHealthSnapshot {
        try queue.sync {
            try validateBinaries()
            try PersistenceSupport.ensureDirectory(configuration.rootDirectory)
            try PersistenceSupport.ensureDirectory(configuration.socketDirectory)
            if !FileManager.default.fileExists(
                atPath: configuration.dataDirectory.appendingPathComponent("PG_VERSION").path
            ) {
                try PersistenceSupport.ensureDirectory(configuration.dataDirectory.deletingLastPathComponent())
                try runProcess(
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
                try runProcess(
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
            return health
        }
    }

    public func shutdownIfRunning() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: configuration.dataDirectory.path) else { return }
            _ = try? runProcess(
                executable: configuration.pgCtlBinary,
                arguments: ["-D", configuration.dataDirectory.path, "stop", "-m", "fast"]
            )
            cachedHealth = nil
        }
    }

    public func connectionInfo() throws -> ManagedPostgresConnectionInfo {
        _ = try bootstrapIfNeeded()
        return ManagedPostgresConnectionInfo(
            databaseName: configuration.databaseName,
            userName: configuration.userName,
            host: configuration.socketDirectory.path,
            port: configuration.port
        )
    }

    private func validateBinaries() throws {
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
        if isHealthy(databaseName: configuration.databaseName) {
            return
        }
        _ = try? runPSQL(databaseName: "postgres", sql: "SELECT 1;")
        do {
            try runProcess(
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw PersistenceBootstrapError.bootstrapFailed(
                ([output, error].joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
