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

    func runStream(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?,
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
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
        let iteratorHolder = IteratorHolder(stream)
        var hasReceivedAnyEvent = false
        var emittedFirstText = false
        // Gemini CLI may take longer for the first token (slow model, network)
        let firstEventTimeout = provider.id == "gemini-cli" ? 120 : 60
        let inactivityTimeout = 300

        while true {
            let timeout = hasReceivedAnyEvent ? inactivityTimeout : firstEventTimeout
            let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                try await iteratorHolder.next()
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
    ) async {
        await setState(.delegatedSwarm)
        do {
            var swarmFull = ""
            let swarmStream = try await swarmProvider.send(prompt: task, context: context, imageURLs: imageURLs)
            let swarmIteratorHolder = IteratorHolder(swarmStream)
            var swarmReceivedAny = false
            let swarmStartedAt = Date()
            var swarmFirstTextLogged = false
            let swarmFirstEventTimeout = swarmProvider.id == "gemini-cli" ? 120 : 60
            while true {
                let timeout = swarmReceivedAny ? 300 : swarmFirstEventTimeout
                let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                    try await swarmIteratorHolder.next()
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
                case .raw(let t, let p):
                    await MainActor.run {
                        onRaw(t, p, swarmProvider.id)
                    }
                default:
                    break
                }
                await Task.yield()
            }

            guard let agentProvider = agentFollowUpProvider else {
                await setState(.completed)
                return
            }

            await setState(.followUp)
            let followUpPrompt = """
            Original request: \(originalPrompt)

            You delegated to swarm: \(task)

            Swarm result:
            \(swarmFull)

            Integrate what was done into the conversation context and continue.
            """
            var follow = ""
            let followStream = try await agentProvider.send(prompt: followUpPrompt, context: context, imageURLs: nil)
            let followIteratorHolder = IteratorHolder(followStream)
            var followReceivedAny = false
            let followStartedAt = Date()
            var followFirstTextLogged = false
            let followFirstEventTimeout = agentProvider.id == "gemini-cli" ? 120 : 60
            while true {
                let timeout = followReceivedAny ? 300 : followFirstEventTimeout
                let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                    try await followIteratorHolder.next()
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
                case .raw(let t, let p):
                    await MainActor.run {
                        onRaw(t, p, agentProvider.id)
                    }
                default:
                    break
                }
                await Task.yield()
            }
            await setState(.completed)
        } catch {
            await MainActor.run {
                onError("[Error swarm/follow-up: \(error.localizedDescription)]")
            }
            await setState(.error)
        }
    }

    private func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
