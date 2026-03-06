import Foundation

@MainActor
final class DebugProjectionStoreBinding {
    weak var store: DebugStore?
    let applyEffects: @MainActor (DebugProjectionUIEffects) -> Void

    init(
        store: DebugStore,
        applyEffects: @escaping @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
    ) {
        self.store = store
        self.applyEffects = applyEffects
    }
}
