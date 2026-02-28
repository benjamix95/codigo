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

final class ConversationFlowCoordinator: ObservableObject {
    private enum StreamTimeoutPolicy {
        static let firstEventTimeoutSecDefault = 90
        static let firstEventTimeoutSecGemini = 180
        static let inactivityTimeoutSec = 1800
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
        var full = ""
        let stream = try await provider.send(prompt: prompt, context: context, attachments: attachments)
        let iteratorHolder = IteratorHolder(stream)
        var hasReceivedAnyEvent = false
        var emittedFirstText = false
        // Keep watchdog permissive for long multi-agent/tool runs.
        let firstEventTimeout = provider.id == "gemini-cli"
            ? StreamTimeoutPolicy.firstEventTimeoutSecGemini
            : StreamTimeoutPolicy.firstEventTimeoutSecDefault
        let inactivityTimeout = StreamTimeoutPolicy.inactivityTimeoutSec
        var initialNoEventRetries = 0
        var inactivityStallRetries = 0

        while true {
            let timeout = hasReceivedAnyEvent ? inactivityTimeout : firstEventTimeout
            let maybeEvent: StreamEvent?
            do {
                maybeEvent = try await nextEvent(withinSeconds: timeout) {
                    try await iteratorHolder.next()
                }
                // Reset retry budgets after any successful poll.
                initialNoEventRetries = 0
                inactivityStallRetries = 0
            } catch let timeoutError as StreamWatchdogError {
                switch timeoutError {
                case .noEvents:
                    initialNoEventRetries += 1
                    if initialNoEventRetries <= StreamTimeoutPolicy.maxInitialNoEventRetries {
                        logStreamDiagnostic(
                            "provider=\(provider.id) watchdog=no_events retry=\(initialNoEventRetries)"
                        )
                        continue
                    }
                    throw timeoutError
                case .stalled:
                    inactivityStallRetries += 1
                    if inactivityStallRetries <= StreamTimeoutPolicy.maxInactivityStallRetries {
                        logStreamDiagnostic(
                            "provider=\(provider.id) watchdog=stalled retry=\(inactivityStallRetries)"
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
                full += d
                let snapshot = full
                await MainActor.run {
                    onText(snapshot)
                }
            case .error(let e):
                full += "\n\n[Error: \(e)]"
                let snapshot = full
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
        return full
    }

    private func nextEvent<T>(
        withinSeconds timeout: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                throw timeout <= 60
                    ? StreamWatchdogError.noEvents(timeout: timeout)
                    : StreamWatchdogError.stalled(timeout: timeout)
            }
            guard let value = try await group.next() else {
                throw StreamWatchdogError.stalled(timeout: timeout)
            }
            group.cancelAll()
            return value
        }
    }

    private func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
