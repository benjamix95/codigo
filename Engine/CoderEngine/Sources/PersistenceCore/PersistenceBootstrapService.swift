import Foundation

public final class PersistenceBootstrapService {
    public static let shared = PersistenceBootstrapService()

    private let queue = DispatchQueue(label: "CoderEngine.Persistence.Bootstrap")
    private let store: PostgresPersistenceStore
    private var cachedReport: PersistenceMigrationReport?
    private var cachedHealth: PersistenceHealthSnapshot?

    public init(store: PostgresPersistenceStore = .shared) {
        self.store = store
    }

    public func bootstrapIfNeeded() throws -> PersistenceMigrationReport {
        try queue.sync {
            if let cachedReport {
                return cachedReport
            }
            let report = try store.applyMigrationAndImportIfNeeded()
            cachedReport = report
            cachedHealth = PersistenceHealthSnapshot(
                isReady: true,
                databaseName: ManagedPostgresConfiguration.default.databaseName,
                host: ManagedPostgresConfiguration.default.socketDirectory.path,
                port: ManagedPostgresConfiguration.default.port,
                dataDirectoryPath: ManagedPostgresConfiguration.default.dataDirectory.path,
                socketDirectoryPath: ManagedPostgresConfiguration.default.socketDirectory.path,
                schemaVersion: report.schemaVersion,
                importedLegacyData: report.importedLegacyData,
                lastMigrationAt: report.appliedAt,
                lastImportAt: report.appliedAt,
                lastError: nil
            )
            return report
        }
    }

    public func healthSnapshot() -> PersistenceHealthSnapshot? {
        queue.sync { cachedHealth }
    }
}
