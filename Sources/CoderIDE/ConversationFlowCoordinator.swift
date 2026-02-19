import Foundation
import CoderEngine

@MainActor
final class ConversationFlowCoordinator: ObservableObject {
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
        onError: @escaping (String) -> Void
    ) async throws -> (fullText: String, pendingSwarmTask: String?) {
        startStreaming()
        var full = ""
        var pendingSwarmTask: String?
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
        for try await ev in stream {
            switch ev {
            case .textDelta(let d):
                full += d
                onText(full)
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
        finish()
        return (full, pendingSwarmTask)
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
            for try await ev in swarmStream {
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
            for try await ev in followStream {
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
