import Foundation
import CoderEngine

/// Manages live-fetched OpenAI model list with fallback to static catalog.
@MainActor
final class OpenAIModelPickerStore: ObservableObject {
    @Published private(set) var models: [String] = openAIModels
    @Published private(set) var isLoading = false

    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    static let shared = OpenAIModelPickerStore()

    deinit {
        loadTask?.cancel()
    }

    func loadIfNeeded(apiKey: String) {
        guard loadTask == nil, !hasLoaded else { return }
        guard !apiKey.isEmpty else { return }
        isLoading = true
        loadTask = Task { [weak self] in
            let fetched = await OpenAIModelsFetcher.fetchModels(apiKey: apiKey)
            guard !Task.isCancelled, let self else { return }
            if !fetched.isEmpty {
                self.models = fetched
            }
            self.hasLoaded = true
            self.isLoading = false
            self.loadTask = nil
        }
    }

    func reload(apiKey: String) {
        loadTask?.cancel()
        loadTask = nil
        hasLoaded = false
        OpenAIModelsFetcher.invalidateCache()
        loadIfNeeded(apiKey: apiKey)
    }
}
