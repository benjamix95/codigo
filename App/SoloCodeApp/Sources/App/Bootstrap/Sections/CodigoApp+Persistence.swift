import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func bootstrapPersistenceIfNeeded() {
        guard PersistenceFeatureFlags.isEnabled else { return }
        PersistenceBootstrapService.shared.beginBootstrapIfNeeded()
    }
}
