import Foundation

public struct ManagedPostgresConfiguration: Sendable, Equatable {
    public let rootDirectory: URL
    public let dataDirectory: URL
    public let socketDirectory: URL
    public let logFile: URL
    public let databaseName: String
    public let userName: String
    public let port: Int
    public let postgresBinary: String
    public let initdbBinary: String
    public let pgCtlBinary: String
    public let createdbBinary: String
    public let psqlBinary: String

    public init(
        rootDirectory: URL,
        dataDirectory: URL,
        socketDirectory: URL,
        logFile: URL,
        databaseName: String,
        userName: String,
        port: Int,
        postgresBinary: String,
        initdbBinary: String,
        pgCtlBinary: String,
        createdbBinary: String,
        psqlBinary: String
    ) {
        self.rootDirectory = rootDirectory
        self.dataDirectory = dataDirectory
        self.socketDirectory = socketDirectory
        self.logFile = logFile
        self.databaseName = databaseName
        self.userName = userName
        self.port = port
        self.postgresBinary = postgresBinary
        self.initdbBinary = initdbBinary
        self.pgCtlBinary = pgCtlBinary
        self.createdbBinary = createdbBinary
        self.psqlBinary = psqlBinary
    }

    public static var `default`: ManagedPostgresConfiguration {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let root = appSupport
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("postgres", isDirectory: true)
        let userName = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return ManagedPostgresConfiguration(
            rootDirectory: root,
            dataDirectory: root.appendingPathComponent("data", isDirectory: true),
            socketDirectory: root.appendingPathComponent("socket", isDirectory: true),
            logFile: root.appendingPathComponent("postgres.log"),
            databaseName: "solocode_persistence",
            userName: userName,
            port: 55432,
            postgresBinary: "/opt/homebrew/bin/postgres",
            initdbBinary: "/opt/homebrew/bin/initdb",
            pgCtlBinary: "/opt/homebrew/bin/pg_ctl",
            createdbBinary: "/opt/homebrew/bin/createdb",
            psqlBinary: "/opt/homebrew/bin/psql"
        )
    }
}

public struct ManagedPostgresConnectionInfo: Sendable, Equatable {
    public let databaseName: String
    public let userName: String
    public let host: String
    public let port: Int
}

public struct PersistenceHealthSnapshot: Sendable, Codable, Equatable {
    public let isReady: Bool
    public let databaseName: String
    public let host: String
    public let port: Int
    public let dataDirectoryPath: String
    public let socketDirectoryPath: String
    public let schemaVersion: Int
    public let importedLegacyData: Bool
    public let lastMigrationAt: Date?
    public let lastImportAt: Date?
    public let lastError: String?
}

public struct PersistenceMigrationReport: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let appliedAt: Date
    public let importedLegacyData: Bool
    public let importedEntities: [String: Int]
}

public enum PersistenceBootstrapError: LocalizedError, Equatable {
    case binaryMissing(String)
    case bootstrapFailed(String)
    case healthCheckFailed(String)
    case databaseCreationFailed(String)
    case migrationFailed(String)
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryMissing(let value):
            return "Missing PostgreSQL binary: \(value)"
        case .bootstrapFailed(let value):
            return "PostgreSQL bootstrap failed: \(value)"
        case .healthCheckFailed(let value):
            return "PostgreSQL health check failed: \(value)"
        case .databaseCreationFailed(let value):
            return "PostgreSQL database creation failed: \(value)"
        case .migrationFailed(let value):
            return "PostgreSQL migration failed: \(value)"
        case .importFailed(let value):
            return "Legacy persistence import failed: \(value)"
        }
    }
}

public enum PersistenceFeatureFlags {
    public static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["SOLOCODE_DISABLE_POSTGRES_PERSISTENCE"] == "1" {
            return false
        }
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        if isRunningTests {
            return environment["SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS"] == "1"
        }
        return true
    }
}

enum PersistenceSupport {
    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func sqlLiteral(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "''") + "'"
    }

    static func jsonLiteral<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PersistenceBootstrapError.migrationFailed("Unable to encode JSON payload.")
        }
        return sqlLiteral(string)
    }

    static func decodeJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
