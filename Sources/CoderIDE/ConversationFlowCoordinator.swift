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
        case delegatedSwarm = "delegated_swarm"
        case followUp
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
    func markDelegatedSwarm() {
        state = .delegatedSwarm
    }

    @MainActor
    func markFollowUp() {
        state = .followUp
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

    private func isCancellationErrorMessage(_ message: String) -> Bool {
        let normalized = message
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)

        return normalized.contains("cancel")
            || normalized.contains("interrot")
            || normalized.contains("aborted")
            || normalized.contains("stop")
            || normalized.contains("interruption")
            || normalized.contains("interrupted")
            || normalized.contains("user") && normalized.contains("cancel")
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
    ) async throws -> (fullText: String, pendingSwarmTask: String?) {
        let streamStartedAt = Date()
        await setState(.streaming)
        await MainActor.run {
            onSignal?(.streamStarted(streamStartedAt))
        }
        var full = ""
        var pendingSwarmTask: String?
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
                if t == "coderide_invoke_swarm", let task = p["task"], !task.isEmpty {
                    pendingSwarmTask = task
                }
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
        return (full, pendingSwarmTask)
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

    func runDelegatedSwarm(
        task: String,
        swarmProvider: any LLMProvider,
        context: WorkspaceContext,
        imageURLs: [URL]?,
        agentFollowUpProvider: (any LLMProvider)?,
        originalPrompt: String,
        onSwarmText: @escaping (String) -> Void,
        onRaw: @escaping (String, [String: String], String) -> Void,
        onFollowUpText: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) async -> State {
        await setState(.delegatedSwarm)
        do {
            var wasCancelled = false

            var swarmFull = ""
            let swarmStream = try await swarmProvider.send(prompt: task, context: context, imageURLs: imageURLs)
            let swarmIteratorHolder = IteratorHolder(swarmStream)
            var swarmReceivedAny = false
            let swarmStartedAt = Date()
            var swarmFirstTextLogged = false
            let swarmFirstEventTimeout = swarmProvider.id == "gemini-cli"
                ? StreamTimeoutPolicy.firstEventTimeoutSecGemini
                : StreamTimeoutPolicy.firstEventTimeoutSecDefault
            var swarmNoEventRetries = 0
            var swarmStallRetries = 0
            swarmLoop: while true {
                let timeout = swarmReceivedAny ? StreamTimeoutPolicy.inactivityTimeoutSec : swarmFirstEventTimeout
                let maybeEvent: StreamEvent?
                do {
                    maybeEvent = try await nextEvent(withinSeconds: timeout) {
                        try await swarmIteratorHolder.next()
                    }
                    swarmNoEventRetries = 0
                    swarmStallRetries = 0
                } catch let timeoutError as StreamWatchdogError {
                    switch timeoutError {
                    case .noEvents:
                        swarmNoEventRetries += 1
                        if swarmNoEventRetries <= StreamTimeoutPolicy.maxInitialNoEventRetries {
                            logStreamDiagnostic(
                                "provider=\(swarmProvider.id) delegated_swarm_watchdog=no_events retry=\(swarmNoEventRetries)"
                            )
                            continue
                        }
                        throw timeoutError
                    case .stalled:
                        swarmStallRetries += 1
                        if swarmStallRetries <= StreamTimeoutPolicy.maxInactivityStallRetries {
                            logStreamDiagnostic(
                                "provider=\(swarmProvider.id) delegated_swarm_watchdog=stalled retry=\(swarmStallRetries)"
                            )
                            await Task.yield()
                            continue
                        }
                        throw timeoutError
                    }
                }
                guard let ev = maybeEvent else { break }
                if !swarmReceivedAny {
                    let firstEventMs = Int(Date().timeIntervalSince(swarmStartedAt) * 1_000)
                    logStreamDiagnostic(
                        "provider=\(swarmProvider.id) delegated_swarm_first_event_ms=\(firstEventMs)"
                    )
                }
                swarmReceivedAny = true
                switch ev {
                case .textDelta(let d):
                    if !swarmFirstTextLogged {
                        swarmFirstTextLogged = true
                        let firstTextMs = Int(Date().timeIntervalSince(swarmStartedAt) * 1_000)
                        logStreamDiagnostic(
                            "provider=\(swarmProvider.id) delegated_swarm_first_text_ms=\(firstTextMs)"
                        )
                    }
                    swarmFull += d
                    let snapshot = swarmFull
                    await MainActor.run {
                        onSwarmText(snapshot)
                    }
                case .error(let e):
                    swarmFull += "\n\n[Error: \(e)]"
                    let snapshot = swarmFull
                    await MainActor.run {
                        onError(snapshot)
                    }
                    if isCancellationErrorMessage(e) {
                        wasCancelled = true
                        break swarmLoop
                    }
                case .raw(let t, let p):
                    await MainActor.run {
                        onRaw(t, p, swarmProvider.id)
                    }
                default:
                    break
                }
                await Task.yield()
            }

            if wasCancelled {
                await setState(.interrupted)
                return .interrupted
            }

            guard let agentProvider = agentFollowUpProvider else {
                await setState(.completed)
                return .completed
            }

            await setState(.followUp)
            let followUpPrompt = """
            Original request: \(originalPrompt)

            You delegated to swarm: \(task)

            Swarm result:
            \(swarmFull)

            Integrate what was done into the conversation context and continue.
            IMPORTANT: Before starting any implementation or code changes, you MUST first create a TodoWrite list with all the concrete tasks to complete. The user tracks progress via the LiveCard — create the TodoWrite immediately after reviewing the swarm results, then proceed task by task.
            """
            var follow = ""
            let followStream = try await agentProvider.send(prompt: followUpPrompt, context: context, imageURLs: nil)
            let followIteratorHolder = IteratorHolder(followStream)
            var followReceivedAny = false
            let followStartedAt = Date()
            var followFirstTextLogged = false
            let followFirstEventTimeout = agentProvider.id == "gemini-cli"
                ? StreamTimeoutPolicy.firstEventTimeoutSecGemini
                : StreamTimeoutPolicy.firstEventTimeoutSecDefault
            var followNoEventRetries = 0
            var followStallRetries = 0
            followUpLoop: while true {
                let timeout = followReceivedAny ? StreamTimeoutPolicy.inactivityTimeoutSec : followFirstEventTimeout
                let maybeEvent: StreamEvent?
                do {
                    maybeEvent = try await nextEvent(withinSeconds: timeout) {
                        try await followIteratorHolder.next()
                    }
                    followNoEventRetries = 0
                    followStallRetries = 0
                } catch let timeoutError as StreamWatchdogError {
                    switch timeoutError {
                    case .noEvents:
                        followNoEventRetries += 1
                        if followNoEventRetries <= StreamTimeoutPolicy.maxInitialNoEventRetries {
                            logStreamDiagnostic(
                                "provider=\(agentProvider.id) delegated_followup_watchdog=no_events retry=\(followNoEventRetries)"
                            )
                            continue
                        }
                        throw timeoutError
                    case .stalled:
                        followStallRetries += 1
                        if followStallRetries <= StreamTimeoutPolicy.maxInactivityStallRetries {
                            logStreamDiagnostic(
                                "provider=\(agentProvider.id) delegated_followup_watchdog=stalled retry=\(followStallRetries)"
                            )
                            await Task.yield()
                            continue
                        }
                        throw timeoutError
                    }
                }
                guard let ev = maybeEvent else { break }
                if !followReceivedAny {
                    let firstEventMs = Int(Date().timeIntervalSince(followStartedAt) * 1_000)
                    logStreamDiagnostic(
                        "provider=\(agentProvider.id) delegated_followup_first_event_ms=\(firstEventMs)"
                    )
                }
                followReceivedAny = true
                switch ev {
                case .textDelta(let d):
                    if !followFirstTextLogged {
                        followFirstTextLogged = true
                        let firstTextMs = Int(Date().timeIntervalSince(followStartedAt) * 1_000)
                        logStreamDiagnostic(
                            "provider=\(agentProvider.id) delegated_followup_first_text_ms=\(firstTextMs)"
                        )
                    }
                    follow += d
                    let snapshot = follow
                    await MainActor.run {
                        onFollowUpText(snapshot)
                    }
                case .error(let e):
                    follow += "\n\n[Error: \(e)]"
                    let snapshot = follow
                    await MainActor.run {
                        onError(snapshot)
                    }
                    if isCancellationErrorMessage(e) {
                        wasCancelled = true
                        break followUpLoop
                    }
                case .raw(let t, let p):
                    await MainActor.run {
                        onRaw(t, p, agentProvider.id)
                    }
                default:
                    break
                }
                await Task.yield()
            }

            if wasCancelled {
                await setState(.interrupted)
                return .interrupted
            }

            await setState(.completed)
            return .completed
        } catch {
            await MainActor.run {
                onError("[Error swarm/follow-up: \(error.localizedDescription)]")
            }
            if isCancellationError(error) {
                await setState(.interrupted)
                return .interrupted
            }
            await setState(.error)
            return .error
        }
    }

    private func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
