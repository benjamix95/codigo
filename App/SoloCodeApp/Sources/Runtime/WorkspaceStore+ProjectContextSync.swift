import Foundation
import CoderEngine

/// Legacy flow coordinator retained as a Swift adapter around the Rust-backed
/// direct stream runtime while provider transport remains in Swift.
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

    let initialEventTimeoutOverride: Int?
    let activityTimeoutOverride: Int?
    let initialRetryOverride: Int?
    let stallRetryOverride: Int?
    var directRuntimeSnapshot: MainChatRuntimeSnapshotBridge?
    var planRuntimeSnapshot: MainChatRuntimeSnapshotBridge?

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

    @Published private(set) var state: State = .idle

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

    private func setState(_ newState: State) async {
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

    private func runRustTransportStream(
        provider: MainChatRustTransportProvider,
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?,
        onText: @escaping (String) -> Void,
        onRaw: @escaping (String, [String: String], String) -> Void,
        onError: @escaping (String) -> Void,
        onSignal: ((StreamSignal) -> Void)?,
        runtimeSnapshot: inout MainChatRuntimeSnapshotBridge,
        turnState: inout ChatTurnState
    ) async throws -> String {
        let sessionId = try provider.startRuntimeSession(
            prompt: prompt,
            context: context,
            attachments: attachments
        )

        while true {
            let timeoutMs = max(1, (runtimeSnapshot.currentPollTimeoutSeconds ?? 90) * 1000)
            guard let response = provider.pollRuntime(
                sessionId: sessionId,
                providerId: provider.id,
                snapshot: runtimeSnapshot,
                timeoutMs: timeoutMs
            ), let nextSnapshot = response.runtimeSnapshot else {
                await setState(.error)
                throw StreamExecutionError.providerError("Rust main chat provider runtime poll unavailable.")
            }

            runtimeSnapshot = nextSnapshot
            setDirectRuntimeSnapshot(nextSnapshot)
            turnState = nextSnapshot.turnState.chatTurnState
            let eventTimestamp = Date()

            for signal in response.signals {
                await MainActor.run {
                    switch signal {
                    case .firstEvent:
                        onSignal?(.firstEvent(eventTimestamp))
                    case .firstTextDelta:
                        onSignal?(.firstTextDelta(eventTimestamp))
                    case .streamCompleted:
                        onSignal?(.streamCompleted(eventTimestamp))
                    }
                }
            }

            for event in response.uiEvents {
                switch event.kind {
                case .started:
                    break
                case .textDelta, .textReplace:
                    let textSnapshot = turnState.primaryTextSnapshot
                    await MainActor.run { onText(textSnapshot) }
                case .raw:
                    await MainActor.run { onRaw(event.rawType ?? "provider_raw", event.payload, provider.id) }
                case .error:
                    let message = event.text.isEmpty
                        ? (runtimeSnapshot.output?.terminalError ?? "Provider stream failed")
                        : event.text
                    let textSnapshot = turnState.primaryTextSnapshot
                    await MainActor.run { onError(textSnapshot + "\n\n[Error: \(message)]") }
                    await setState(.error)
                    throw StreamExecutionError.providerError(message)
                case .completed:
                    await setState(.completed)
                    return turnState.primaryTextSnapshot
                }
            }

            await Task.yield()
        }
    }

    private static func runtimeEventKind(_ event: StreamEvent) -> String {
        switch event {
        case .textDelta, .textReplace:
            return event.isReplace ? "textReplace" : "textDelta"
        case .started:
            return "started"
        case .completed:
            return "completed"
        case .error:
            return "error"
        case .raw:
            return "raw"
        }
    }

    private static func runtimePayload(_ event: StreamEvent) -> [String: String] {
        switch event {
        case .textDelta(let delta):
            return ["delta": delta, "stream_id": "main"]
        case .textReplace(let replacement):
            return ["replacement": replacement, "stream_id": "main"]
        case .raw(_, let payload):
            return payload
        case .error(let message):
            return ["error": message]
        case .started, .completed:
            return [:]
        }
    }
}

private extension MainChatRuntimeSnapshotBridge {
    var currentPollTimeoutSeconds: Int? {
        guard let directStream else { return nil }
        return directStream.hasReceivedAnyEvent ? directStream.activityTimeoutSec : directStream.firstEventTimeoutSec
    }
}

private extension StreamEvent {
    var isReplace: Bool {
        if case .textReplace = self {
            return true
        }
        return false
    }
}
