import Foundation

public final class PostgresPersistenceStore {
    public static let shared = PostgresPersistenceStore()

    private let queue = DispatchQueue(label: "CoderEngine.Persistence.Store")
    private let postgresService: ManagedPostgresService

    public init(postgresService: ManagedPostgresService = .shared) {
        self.postgresService = postgresService
    }

    public func ensureReady() throws {
        try queue.sync {
            _ = try postgresService.bootstrapIfNeeded()
            let currentVersion = try schemaVersion()
            if currentVersion < PersistenceSchema.version {
                try postgresService.runPSQL(
                    databaseName: postgresService.connectionInfo().databaseName,
                    sql: PersistenceSchema.migrationSQL()
                )
                let insertSQL = """
                INSERT INTO schema_migrations(version, applied_at)
                VALUES (\(PersistenceSchema.version), NOW())
                ON CONFLICT (version) DO NOTHING;
                """
                try postgresService.runPSQL(
                    databaseName: postgresService.connectionInfo().databaseName,
                    sql: insertSQL
                )
            }
        }
    }

    public func schemaVersion() throws -> Int {
        let exists = try postgresService.runPSQL(
            databaseName: postgresService.connectionInfo().databaseName,
            sql: "SELECT to_regclass('public.schema_migrations') IS NOT NULL;"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard exists == "t" else { return 0 }

        let result = try postgresService.runPSQL(
            databaseName: postgresService.connectionInfo().databaseName,
            sql: "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"
        )
        return Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func execute(sql: String) throws -> String {
        try ensureReady()
        return try postgresService.runPSQL(
            databaseName: postgresService.connectionInfo().databaseName,
            sql: sql
        )
    }

    func querySingleJSON<T: Decodable>(_ sql: String, as type: T.Type) throws -> T? {
        let result = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }
        return try PersistenceSupport.decodeJSON(result, as: type)
    }

    func querySingleJSONString(_ sql: String) throws -> String? {
        let result = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    func queryJSONArray<T: Decodable>(_ sql: String, as type: [T].Type) throws -> [T] {
        let result = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return [] }
        return try PersistenceSupport.decodeJSON(result, as: type)
    }

    func queryJSONArrayString(_ sql: String) throws -> String {
        try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func applyMigrationAndImportIfNeeded() throws -> PersistenceMigrationReport {
        try ensureReady()
        return try LegacyPersistenceImportService(store: self).importIfNeeded()
    }

    func sqlTimestamp(_ value: Date?) -> String {
        guard let value else { return "NULL" }
        return PersistenceSupport.sqlLiteral(ISO8601DateFormatter().string(from: value))
    }

    func sqlNullable(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "NULL" }
        return PersistenceSupport.sqlLiteral(value)
    }

    func sqlInteger(_ value: Int?) -> String {
        value.map(String.init) ?? "NULL"
    }
}
