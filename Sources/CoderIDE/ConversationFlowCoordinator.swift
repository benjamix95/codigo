import Foundation
import CoderEngine

/// Sendable wrapper for AsyncSequence iterator, used to avoid capturing `var` in concurrent closures.
private final class IteratorHolder<Stream: AsyncSequence>: @unchecked Sendable {
    private var iterator: Stream.AsyncIterator

    init(_ stream: Stream) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Stream.AsyncIterator.Element? {
        try await iterator.next()
    }
}

private enum StreamWatchdogError: LocalizedError {
    case noEvents(timeout: Int)
    case stalled(timeout: Int)

    var errorDescription: String? {
        switch self {
        case .noEvents(let timeout):
            return "No events received from provider within \(timeout)s."
        case .stalled(let timeout):
            return "Stream stalled: no updates for \(timeout)s."
        }
    }
}

private enum StreamIterationState: Error {
    case ended
}

final class ConversationFlowCoordinator: ObservableObject {
    private let initialEventTimeoutOverride: Int?
    private let activityTimeoutOverride: Int?
    private let initialRetryOverride: Int?
    private let stallRetryOverride: Int?

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

    private enum StreamTimeoutPolicy {
        static let firstEventTimeoutSecDefault = 90
        static let firstEventTimeoutSecGemini = 180
        static let activityTimeoutSec = 1800
        static let maxInitialNoEventRetries = 4
        static let maxInactivityStallRetries = 12
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
    func startStreaming() {
        state = .streaming
    }

    @MainActor
    func finish() {
        state = .completed
    }

    @MainActor
    func fail() {
        state = .error
    }

    @MainActor
    func interrupt() {
        state = .interrupted
    }

    @MainActor
    func reset() {
        state = .idle
    }

    func normalizeRawEvent(providerId: String, type: String, payload: [String: String], timestamp: Date = .now) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(sourceProvider: providerId, type: type, payload: payload, timestamp: timestamp)
    }

    private func setState(_ newState: State) async {
        await MainActor.run {
            state = newState
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if Task.isCancelled { return true }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        let message = String(describing: error).lowercased()
        return message.contains("cancellation")
            || message.contains("canceled")
            || message.contains("cancelled")
            || message.contains("interrupted")
            || message.contains("interruption")
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
        await MainActor.run {
            onSignal?(.streamStarted(streamStartedAt))
        }
        var fullParts: [String] = []
        var fullPartsLength = 0
        let stream = try await provider.send(prompt: prompt, context: context, attachments: attachments)
        let iteratorHolder = IteratorHolder(stream)
        var hasReceivedAnyEvent = false
        var emittedFirstText = false
        // Keep watchdog permissive for long multi-agent/tool runs.
        let firstEventTimeout = initialEventTimeoutOverride ?? (provider.id == "gemini-cli"
            ? StreamTimeoutPolicy.firstEventTimeoutSecGemini
            : StreamTimeoutPolicy.firstEventTimeoutSecDefault)
        let inactivityTimeout = activityTimeoutOverride ?? StreamTimeoutPolicy.activityTimeoutSec
        let maxInitialNoEventRetries = initialRetryOverride ?? StreamTimeoutPolicy.maxInitialNoEventRetries
        let maxInactivityStallRetries = stallRetryOverride ?? StreamTimeoutPolicy.maxInactivityStallRetries
        var initialNoEventRetries = 0
        var inactivityStallRetries = 0
        var lastEventAt = streamStartedAt

        let clampedFirst = min(3600, max(1, firstEventTimeout))
        let clampedInactivity = min(3600, max(1, inactivityTimeout))
        let clampedInitialRetries = min(max(0, maxInitialNoEventRetries), 100)
        let clampedStallRetries = min(max(0, maxInactivityStallRetries), 100)

        while true {
            let timeout = hasReceivedAnyEvent ? clampedInactivity : clampedFirst
            let maybeEvent: StreamEvent?
            do {
                maybeEvent = try await nextEvent(
                    withinSeconds: timeout,
                    isInitialPoll: !hasReceivedAnyEvent
                ) {
                    try await iteratorHolder.next()
                }
                // Reset retry budgets after any successful poll.
                initialNoEventRetries = 0
                inactivityStallRetries = 0
                lastEventAt = Date()
            } catch let timeoutError as StreamWatchdogError {
                switch timeoutError {
                case .noEvents:
                    initialNoEventRetries += 1
                    if initialNoEventRetries <= clampedInitialRetries {
                        logStreamDiagnostic(
                            "provider=\(provider.id) watchdog=no_events stage=initial retry=\(initialNoEventRetries)/\(clampedInitialRetries) timeout=\(timeout)s"
                        )
                        continue
                    }
                    throw timeoutError
                case .stalled:
                    inactivityStallRetries += 1
                    let elapsedSinceLastEvent = Int(Date().timeIntervalSince(lastEventAt) * 1_000)
                    if inactivityStallRetries <= clampedStallRetries {
                        logStreamDiagnostic(
                            "provider=\(provider.id) watchdog=stalled stage=post-first retry=\(inactivityStallRetries)/\(clampedStallRetries) timeout=\(timeout)s elapsed_ms=\(elapsedSinceLastEvent)"
                        )
                        await Task.yield()
                        continue
                    }
                    throw timeoutError
                }
            }
            guard let ev = maybeEvent else { break }
            if !hasReceivedAnyEvent {
                let firstEventAt = Date()
                let firstEventDelay = firstEventAt.timeIntervalSince(streamStartedAt)
                logStreamDiagnostic(
                    "provider=\(provider.id) first_event_ms=\(Int(firstEventDelay * 1_000))"
                )
                await MainActor.run {
                    onSignal?(.firstEvent(firstEventAt))
                }
            }
            hasReceivedAnyEvent = true
            switch ev {
            case .textDelta(let d):
                if !emittedFirstText {
                    emittedFirstText = true
                    let firstTextAt = Date()
                    let firstTextDelay = firstTextAt.timeIntervalSince(streamStartedAt)
                    logStreamDiagnostic(
                        "provider=\(provider.id) first_text_ms=\(Int(firstTextDelay * 1_000))"
                    )
                    await MainActor.run {
                        onSignal?(.firstTextDelta(firstTextAt))
                    }
                }
                if fullPartsLength + d.count <= 500_000 { fullParts.append(d); fullPartsLength += d.count }
                let snapshot = fullParts.joined()
                await MainActor.run {
                    onText(snapshot)
                }
            case .error(let e):
                let errStr = "\n\n[Error: \(e)]"
                if fullPartsLength + errStr.count <= 500_000 { fullParts.append(errStr); fullPartsLength += errStr.count }
                let snapshot = fullParts.joined()
                await MainActor.run {
                    onError(snapshot)
                }
            case .raw(let t, let p):
                await MainActor.run {
                    onRaw(t, p, provider.id)
                }
            default:
                break
            }
            // Fairness: yield the turn even when many raw/non-text events arrive.
            await Task.yield()
        }
        let completedAt = Date()
        let totalMs = Int(completedAt.timeIntervalSince(streamStartedAt) * 1_000)
        logStreamDiagnostic("provider=\(provider.id) stream_completed_ms=\(totalMs)")
        await MainActor.run {
            onSignal?(.streamCompleted(completedAt))
        }
        await setState(.completed)
        return fullParts.joined()
    }

    private func nextEvent(
        withinSeconds timeout: Int,
        isInitialPoll: Bool,
        operation: @escaping @Sendable () async throws -> StreamEvent?
    ) async throws -> StreamEvent? {
        try await withThrowingTaskGroup(of: StreamEvent.self) { group in
            group.addTask {
                guard let value = try await operation() else { throw StreamIterationState.ended }
                return value
            }
            group.addTask {
                let safeTimeout = max(1, timeout)
                try await Task.sleep(nanoseconds: UInt64(safeTimeout) * 1_000_000_000)
                throw isInitialPoll
                    ? StreamWatchdogError.noEvents(timeout: timeout)
                    : StreamWatchdogError.stalled(timeout: timeout)
            }
            do {
                guard let value = try await group.next() else {
                    throw StreamWatchdogError.stalled(timeout: timeout)
                }
                group.cancelAll()
                return value
            } catch StreamIterationState.ended {
                group.cancelAll()
                return nil
            }
        }
    }

    private func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
