import Foundation

public enum PersistenceBootstrapStatus: String, Sendable, Codable, Equatable {
    case idle
    case warming
    case ready
    case failed
}

public final class PersistenceBootstrapService {
    public static let shared = PersistenceBootstrapService()

    private let queue = DispatchQueue(label: "CoderEngine.Persistence.Bootstrap")
    private let store: PostgresPersistenceStore
    private var cachedReport: PersistenceMigrationReport?
    private var cachedHealth: PersistenceHealthSnapshot?
    private var status: PersistenceBootstrapStatus = .idle
    private var lastErrorMessage: String?

    public init(store: PostgresPersistenceStore = .shared) {
        self.store = store
    }

    public func bootstrapIfNeeded() throws -> PersistenceMigrationReport {
        try queue.sync {
            if let cachedReport {
                status = .ready
                return cachedReport
            }
            status = .warming
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
            status = .ready
            lastErrorMessage = nil
            return report
        }
    }

    public func healthSnapshot() -> PersistenceHealthSnapshot? {
        queue.sync { cachedHealth }
    }

    public func statusSnapshot() -> PersistenceBootstrapStatus {
        queue.sync { status }
    }

    public func lastErrorSnapshot() -> String? {
        queue.sync { lastErrorMessage }
    }

    public func beginBootstrapIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try self.bootstrapIfNeeded()
            } catch {
                self.queue.sync {
                    self.status = .failed
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
