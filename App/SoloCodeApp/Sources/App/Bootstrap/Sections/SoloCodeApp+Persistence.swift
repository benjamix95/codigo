import CoderEngine
import Foundation

extension SoloCodeApp {
    @MainActor
    func bootstrapPersistenceIfNeeded() {
        guard PersistenceFeatureFlags.isEnabled else { return }
        PersistenceBootstrapService.shared.beginBootstrapIfNeeded()
    }
}
