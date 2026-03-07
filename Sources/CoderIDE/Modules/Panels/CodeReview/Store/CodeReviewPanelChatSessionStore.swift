import Foundation

@MainActor
final class ReviewPanelChatSessionStore: ObservableObject {
    static let shared = ReviewPanelChatSessionStore()

    @Published private(set) var statesByKey: [String: ReviewPanelChatSessionState] = [:]

    func state(for key: String) -> ReviewPanelChatSessionState {
        statesByKey[key] ?? .empty
    }

    func replaceState(_ state: ReviewPanelChatSessionState, for key: String) {
        statesByKey[key] = state
    }

    func appendMessage(_ message: ReviewPanelMessage, for key: String) {
        var state = state(for: key)
        state.messages.append(message)
        statesByKey[key] = state
    }

    func updateMessage(
        id: UUID,
        for key: String,
        mutate: (inout ReviewPanelMessage) -> Void
    ) {
        var state = state(for: key)
        guard let index = state.messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&state.messages[index])
        statesByKey[key] = state
    }

    func setProcessing(_ isProcessing: Bool, startedAt: Date?, for key: String) {
        var state = state(for: key)
        state.isProcessing = isProcessing
        state.startedAt = startedAt
        statesByKey[key] = state
    }

    func clearState(for key: String) {
        statesByKey[key] = .empty
    }

    func clearAll() {
        statesByKey.removeAll()
    }
}

struct ReviewPanelChatSessionState: Equatable {
    var messages: [ReviewPanelMessage]
    var isProcessing: Bool
    var startedAt: Date?

    static let empty = ReviewPanelChatSessionState(
        messages: [],
        isProcessing: false,
        startedAt: nil
    )
}
