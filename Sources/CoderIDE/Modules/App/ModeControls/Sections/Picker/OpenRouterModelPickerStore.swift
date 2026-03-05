import Combine
import Foundation

@MainActor
final class OpenRouterModelPickerStore: ObservableObject {
    @Published private(set) var allModels: [String]
    @Published private(set) var freeModels: [String]

    private var loadTask: Task<Void, Never>?
    private var hasLoadedRemoteCatalog = false

    init(
        allModels: [String] = OpenRouterModelCatalogSnapshot.fallback.allModels,
        freeModels: [String] = openRouterFreeModels
    ) {
        self.allModels = allModels
        self.freeModels = freeModels
    }

    deinit {
        loadTask?.cancel()
    }

    func loadIfNeeded() {
        guard loadTask == nil, !hasLoadedRemoteCatalog else { return }

        loadTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await OpenRouterModelCatalogService.shared.fetchCatalog()
            guard !Task.isCancelled else { return }
            self.apply(snapshot: snapshot)
        }
    }

    func isFree(_ modelId: String) -> Bool {
        freeModels.contains(modelId)
    }

    private func apply(snapshot: OpenRouterModelCatalogSnapshot) {
        if !snapshot.allModels.isEmpty {
            allModels = snapshot.allModels
        }
        if !snapshot.freeModels.isEmpty {
            freeModels = snapshot.freeModels
        }
        hasLoadedRemoteCatalog = true
        loadTask = nil
    }
}
