import Foundation
import CoderEngine

/// Swift adapter around the Rust-backed direct stream runtime while provider transport remains in Swift.
final class ConversationFlowCoordinator: ObservableObject {
    enum StreamExecutionError: LocalizedError {
        case providerError(String)

        var errorDescription: String? {
            switch self {
            case .providerError(let message):
                return message
            }
        }
    }

    enum StreamSignal {
        case streamStarted(Date)
        case firstEvent(Date)
        case firstTextDelta(Date)
        case streamCompleted(Date)
    }

    enum State: String {
        case idle
        case streaming
        case completed
        case error
        case interrupted
    }

    let initialEventTimeoutOverride: Int?
    let activityTimeoutOverride: Int?
    let initialRetryOverride: Int?
    let stallRetryOverride: Int?
    var directRuntimeSnapshot: MainChatRuntimeSnapshotBridge?
    var planRuntimeSnapshot: MainChatRuntimeSnapshotBridge?

    @Published private(set) var state: State = .idle

    init(
        initialEventTimeoutOverride: Int? = nil,
        activityTimeoutOverride: Int? = nil,
        initialRetryOverride: Int? = nil,
        stallRetryOverride: Int? = nil
    ) {
        self.initialEventTimeoutOverride = initialEventTimeoutOverride
        self.activityTimeoutOverride = activityTimeoutOverride
        self.initialRetryOverride = initialRetryOverride
        self.stallRetryOverride = stallRetryOverride
    }

    @MainActor
    func startStreaming() { state = .streaming }

    @MainActor
    func finish() { state = .completed }

    @MainActor
    func fail() { state = .error }

    @MainActor
    func interrupt() { state = .interrupted }

    @MainActor
    func reset() { state = .idle }

    func normalizeRawEvent(
        providerId: String,
        type: String,
        payload: [String: String],
        timestamp: Date = .now
    ) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(
            sourceProvider: providerId,
            type: type,
            payload: payload,
            timestamp: timestamp
        )
    }

    func directRuntimeSnapshotState() -> MainChatRuntimeSnapshotBridge? { directRuntimeSnapshot }
    func setDirectRuntimeSnapshot(_ snapshot: MainChatRuntimeSnapshotBridge?) { directRuntimeSnapshot = snapshot }
    func planRuntimeSnapshotState() -> MainChatRuntimeSnapshotBridge? { planRuntimeSnapshot }
    func setPlanRuntimeSnapshot(_ snapshot: MainChatRuntimeSnapshotBridge?) { planRuntimeSnapshot = snapshot }

    func setState(_ newState: State) async {
        await MainActor.run { state = newState }
    }

    func runStream(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?,
        onText: @escaping (String) -> Void,
        onRaw: @escaping (String, [String: String], String) -> Void,
        onError: @escaping (String) -> Void,
        onSignal: ((StreamSignal) -> Void)? = nil
    ) async throws -> String {
        let streamStartedAt = Date()
        await setState(.streaming)

        guard let directRuntimeStart = startDirectRuntime(
            providerId: provider.id,
            turnId: provider.id,
            timestamp: streamStartedAt
        ) else {
            await setState(.error)
            throw StreamExecutionError.providerError("Rust main chat direct stream runtime unavailable.")
        }

        setDirectRuntimeSnapshot(directRuntimeStart)
        var runtimeSnapshot = directRuntimeStart
        var turnState = directRuntimeStart.turnState.chatTurnState
        await MainActor.run { onSignal?(.streamStarted(streamStartedAt)) }

        if let rustProvider = provider as? MainChatRustTransportProvider {
            return try await runRustTransportStream(
                provider: rustProvider,
                prompt: prompt,
                context: context,
                attachments: attachments,
                onText: onText,
                onRaw: onRaw,
                onError: onError,
                onSignal: onSignal,
                runtimeSnapshot: &runtimeSnapshot,
                turnState: &turnState
            )
        }

        await setState(.error)
        throw StreamExecutionError.providerError(
            "Legacy generic stream coordinator path retired for main chat runtime."
        )
    }
}
