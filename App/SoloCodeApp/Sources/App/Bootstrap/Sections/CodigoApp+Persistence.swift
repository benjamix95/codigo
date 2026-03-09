import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func bootstrapPersistenceIfNeeded() {
        guard PersistenceFeatureFlags.isEnabled else { return }
        DispatchQueue.global(qos: .utility).async {
            do {
                let report = try PersistenceBootstrapService.shared.bootstrapIfNeeded()
                #if DEBUG
                print("[Persistence] PostgreSQL ready. schema=\(report.schemaVersion) imported=\(report.importedLegacyData)")
                #endif
            } catch {
                #if DEBUG
                print("[Persistence] Bootstrap failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
