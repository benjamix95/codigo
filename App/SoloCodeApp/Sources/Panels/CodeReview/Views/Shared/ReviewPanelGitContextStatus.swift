import Foundation

enum ReviewPanelGitContextStatus: Equatable {
    case idle
    case loading
    case loaded
    case notRepository(message: String)
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var detailMessage: String? {
        switch self {
        case .notRepository(let message), .failed(let message):
            return message
        case .idle, .loading, .loaded:
            return nil
        }
    }
}

@MainActor
private final class ReviewPanelGitContextStatusRegistry {
    var storage: [ObjectIdentifier: ReviewPanelGitContextStatus] = [:]
}

@MainActor
private let reviewPanelGitContextStatusRegistry = ReviewPanelGitContextStatusRegistry()

extension CodeReviewPanelStore {
    var gitContextStatus: ReviewPanelGitContextStatus {
        get { reviewPanelGitContextStatusRegistry.storage[ObjectIdentifier(self)] ?? .idle }
        set { reviewPanelGitContextStatusRegistry.storage[ObjectIdentifier(self)] = newValue }
    }
}
