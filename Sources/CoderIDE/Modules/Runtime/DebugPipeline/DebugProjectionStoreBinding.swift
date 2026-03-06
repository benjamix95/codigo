import Foundation

@MainActor
final class DebugProjectionStoreBinding {
    weak var store: DebugStore?

    init(store: DebugStore) {
        self.store = store
    }
}
