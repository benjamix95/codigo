import Foundation
import CoderEngine

/// Wrapper Sendable per iterator di AsyncSequence, usato per evitare cattura di `var` in closure concorrenti.
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
            return "Nessun evento ricevuto dal provider entro \(timeout)s."
        case .stalled(let timeout):
            return "Stream bloccato: nessun aggiornamento da \(timeout)s."
        }
    }
}

@MainActor
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

    func startStreaming() {
        state = .streaming
    }

    func markDelegatedSwarm() {
        state = .delegatedSwarm
    }

    func markFollowUp() {
        state = .followUp
    }

    func finish() {
        state = .completed
    }

    func fail() {
        state = .error
    }

    func interrupt() {
        state = .interrupted
    }

    func reset() {
        state = .idle
    }

    func normalizeRawEvent(providerId: String, type: String, payload: [String: String], timestamp: Date = .now) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(sourceProvider: providerId, type: type, payload: payload, timestamp: timestamp)
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
        startStreaming()
        onSignal?(.streamStarted(.now))
        var full = ""
        var pendingSwarmTask: String?
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
        let iteratorHolder = IteratorHolder(stream)
        var hasReceivedAnyEvent = false
        var emittedFirstText = false
        // Gemini CLI può impiegare più tempo per il primo token (modello lento, rete)
        let firstEventTimeout = provider.id == "gemini-cli" ? 120 : 60
        let inactivityTimeout = 300

        while true {
            let timeout = hasReceivedAnyEvent ? inactivityTimeout : firstEventTimeout
            let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                try await iteratorHolder.next()
            }
            guard let ev = maybeEvent else { break }
            if !hasReceivedAnyEvent {
                onSignal?(.firstEvent(.now))
            }
            hasReceivedAnyEvent = true
            switch ev {
            case .textDelta(let d):
                if !emittedFirstText {
                    emittedFirstText = true
                    onSignal?(.firstTextDelta(.now))
                }
                full += d
                onText(full)
                await Task.yield()
            case .error(let e):
                full += "\n\n[Errore: \(e)]"
                onError(full)
            case .raw(let t, let p):
                if t == "coderide_invoke_swarm", let task = p["task"], !task.isEmpty {
                    pendingSwarmTask = task
                }
                onRaw(t, p, provider.id)
            default:
                break
            }
        }
        onSignal?(.streamCompleted(.now))
        finish()
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
        markDelegatedSwarm()
        do {
            var swarmFull = ""
            let swarmStream = try await swarmProvider.send(prompt: task, context: context, imageURLs: imageURLs)
            let swarmIteratorHolder = IteratorHolder(swarmStream)
            var swarmReceivedAny = false
            let swarmFirstEventTimeout = swarmProvider.id == "gemini-cli" ? 120 : 60
            while true {
                let timeout = swarmReceivedAny ? 300 : swarmFirstEventTimeout
                let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                    try await swarmIteratorHolder.next()
                }
                guard let ev = maybeEvent else { break }
                swarmReceivedAny = true
                switch ev {
                case .textDelta(let d):
                    swarmFull += d
                    onSwarmText(swarmFull)
                case .error(let e):
                    swarmFull += "\n\n[Errore: \(e)]"
                    onError(swarmFull)
                case .raw(let t, let p):
                    onRaw(t, p, swarmProvider.id)
                default:
                    break
                }
            }

            guard let agentProvider = agentFollowUpProvider else {
                finish()
                return
            }

            markFollowUp()
            let followUpPrompt = """
            Richiesta originale: \(originalPrompt)

            Hai delegato allo swarm: \(task)

            Risultato swarm:
            \(swarmFull)

            Integra quanto fatto nel contesto della conversazione e prosegui.
            """
            var follow = ""
            let followStream = try await agentProvider.send(prompt: followUpPrompt, context: context, imageURLs: nil)
            let followIteratorHolder = IteratorHolder(followStream)
            var followReceivedAny = false
            let followFirstEventTimeout = agentProvider.id == "gemini-cli" ? 120 : 60
            while true {
                let timeout = followReceivedAny ? 300 : followFirstEventTimeout
                let maybeEvent = try await nextEvent(withinSeconds: timeout) {
                    try await followIteratorHolder.next()
                }
                guard let ev = maybeEvent else { break }
                followReceivedAny = true
                switch ev {
                case .textDelta(let d):
                    follow += d
                    onFollowUpText(follow)
                case .error(let e):
                    follow += "\n\n[Errore: \(e)]"
                    onError(follow)
                case .raw(let t, let p):
                    onRaw(t, p, agentProvider.id)
                default:
                    break
                }
            }
            finish()
        } catch {
            onError("[Errore swarm/follow-up: \(error.localizedDescription)]")
            fail()
        }
    }
}
