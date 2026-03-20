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
            return try await runStreamLegacy(
                provider: provider,
                prompt: prompt,
                context: context,
                attachments: attachments,
                onText: onText,
                onRaw: onRaw,
                onError: onError,
                onSignal: onSignal
            )
        }

        setDirectRuntimeSnapshot(directRuntimeStart)
        var runtimeSnapshot = directRuntimeStart
        var turnState = directRuntimeStart.turnState.chatTurnState
        await MainActor.run { onSignal?(.streamStarted(streamStartedAt)) }

        let stream = try await provider.send(prompt: prompt, context: context, attachments: attachments)
        let iteratorHolder = IteratorHolder(stream)
        var pendingNextTask: Task<StreamEvent?, Error>?

        while true {
            let timeout = runtimeSnapshot.currentPollTimeoutSeconds ?? 90
            let maybeEvent: StreamEvent?
            do {
                if pendingNextTask == nil {
                    pendingNextTask = Task { try await iteratorHolder.next() }
                }
                guard let activeTask = pendingNextTask else { break }
                maybeEvent = try await nextEvent(
                    withinSeconds: timeout,
                    isInitialPoll: !runtimeSnapshot.hasReceivedAnyEvent,
                    pendingTask: activeTask
                )
                pendingNextTask = nil
            } catch let timeoutError as StreamWatchdogError {
                guard let timeoutSnapshot = handleDirectRuntimeTimeout(
                    timestamp: Date(),
                    isInitialPoll: !runtimeSnapshot.hasReceivedAnyEvent
                ) else {
                    throw timeoutError
                }
                runtimeSnapshot = timeoutSnapshot
                setDirectRuntimeSnapshot(timeoutSnapshot)
                if timeoutSnapshot.output?.shouldRetryPoll == true {
                    await Task.yield()
                    continue
                }
                await setState(.error)
                throw timeoutError
            }

            guard let event = maybeEvent else { break }
            let hadAnyEvent = runtimeSnapshot.hasReceivedAnyEvent
            let hadFirstText = runtimeSnapshot.emittedFirstText
            if let nextSnapshot = registerDirectRuntimeEvent(
                timestamp: Date(),
                eventKind: Self.runtimeEventKind(event)
            ) {
                runtimeSnapshot = nextSnapshot
                setDirectRuntimeSnapshot(nextSnapshot)
            }
            if !hadAnyEvent, runtimeSnapshot.hasReceivedAnyEvent {
                await MainActor.run { onSignal?(.firstEvent(Date())) }
            }

            switch event {
            case .started:
                break
            case .textDelta(let delta):
                turnState = applyDirectRuntimeStreamEvent(
                    fallbackState: turnState,
                    kind: .textDelta,
                    payload: ["delta": delta, "stream_id": "main"],
                    source: provider.id
                )
                if !hadFirstText, runtimeSnapshot.emittedFirstText {
                    await MainActor.run { onSignal?(.firstTextDelta(Date())) }
                }
                await MainActor.run { onText(turnState.primaryTextSnapshot) }
            case .textReplace(let replacement):
                turnState = applyDirectRuntimeStreamEvent(
                    fallbackState: turnState,
                    kind: .textReplace,
                    payload: ["replacement": replacement, "stream_id": "main"],
                    source: provider.id
                )
                if !hadFirstText, runtimeSnapshot.emittedFirstText {
                    await MainActor.run { onSignal?(.firstTextDelta(Date())) }
                }
                await MainActor.run { onText(turnState.primaryTextSnapshot) }
            case .raw(let type, let payload):
                await MainActor.run { onRaw(type, payload, provider.id) }
            case .error(let message):
                _ = finishDirectRuntime(
                    status: "failed",
                    detail: message,
                    wasCancelled: false,
                    timestamp: Date()
                ).map { snapshot in
                    runtimeSnapshot = snapshot
                    setDirectRuntimeSnapshot(snapshot)
                }
                await MainActor.run { onError(turnState.primaryTextSnapshot + "\n\n[Error: \(message)]") }
                await setState(.error)
                throw StreamExecutionError.providerError(message)
            case .completed:
                let completedAt = Date()
                _ = finishDirectRuntime(
                    status: "completed",
                    detail: nil,
                    wasCancelled: false,
                    timestamp: completedAt
                ).map { snapshot in
                    runtimeSnapshot = snapshot
                    setDirectRuntimeSnapshot(snapshot)
                }
                await MainActor.run { onSignal?(.streamCompleted(completedAt)) }
                await setState(.completed)
                return turnState.primaryTextSnapshot
            }

            await Task.yield()
        }

        let completedAt = Date()
        _ = finishDirectRuntime(
            status: "completed",
            detail: nil,
            wasCancelled: false,
            timestamp: completedAt
        ).map { snapshot in
            setDirectRuntimeSnapshot(snapshot)
        }
        await MainActor.run { onSignal?(.streamCompleted(completedAt)) }
        await setState(.completed)
        return turnState.primaryTextSnapshot
    }

    private static func runtimeEventKind(_ event: StreamEvent) -> MainChatRuntimeEventKind {
        switch event {
        case .textDelta, .textReplace:
            return .text
        case .started:
            return .started
        case .completed:
            return .completed
        case .error:
            return .error
        case .raw:
            return .raw
        }
    }

    private func applyDirectRuntimeStreamEvent(
        fallbackState: ChatTurnState,
        kind: ChatPipelineEventKind,
        payload: [String: String],
        source: String
    ) -> ChatTurnState {
        let event = ChatPipelineEvent(
            conversationId: fallbackState.conversationId,
            assistantMessageId: fallbackState.assistantMessageId,
            turnId: fallbackState.turnId,
            sequence: fallbackState.sequence + 1,
            source: source,
            kind: kind,
            payload: payload
        )
        return MainChatRustBridge.reduce(state: fallbackState, event: event)
            ?? ChatPipelineReducer.apply(state: fallbackState, event: event)
    }
}

private extension MainChatRuntimeSnapshotBridge {
    var hasReceivedAnyEvent: Bool { directStream?.hasReceivedAnyEvent == true }
    var emittedFirstText: Bool { directStream?.emittedFirstText == true }
    var currentPollTimeoutSeconds: Int? {
        guard let directStream else { return nil }
        return directStream.hasReceivedAnyEvent ? directStream.activityTimeoutSec : directStream.firstEventTimeoutSec
    }
}
