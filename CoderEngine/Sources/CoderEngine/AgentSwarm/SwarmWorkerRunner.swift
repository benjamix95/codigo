import Foundation

/// Prompt di sistema per ogni ruolo
private func systemPrompt(for role: AgentRole) -> String {
    switch role {
    case .planner:
        return "Sei il Planner. Analizza la richiesta e produci un piano strutturato con passi chiari. Non scrivere codice."
    case .coder:
        return "Sei il Coder. Esegui le modifiche al codice secondo il piano. Usa gli strumenti disponibili (edit file, run command, etc)."
    case .debugger:
        return "Sei il Debugger. Identifica bug, analizza stack trace e risolvi i problemi. Modifica il codice per correggere."
    case .reviewer:
        return "Sei il Reviewer. Revisiona il codice per stile, best practice e possibili miglioramenti. Suggerisci ottimizzazioni."
    case .docWriter:
        return "Sei il DocWriter. Scrivi documentazione chiara: README, commenti, docstrings. Mantieni coerenza con il codice."
    case .securityAuditor:
        return "Sei il SecurityAuditor. Analizza il codice per vulnerabilità, dipendenze insicure, esposizione di dati sensibili."
    case .testWriter:
        return """
        Sei il TestWriter. Scrivi test per il codice modificato.
        - Swift: usa XCTest, crea file in Tests/<Target>Tests/ con naming *Tests.swift
        - Node: usa Jest o Vitest, file *.test.ts oppure __tests__/*.ts
        - Python: usa pytest, file test_*.py
        Includi: unit test (funzioni isolate), smoke test (avvio/componenti base funzionano), integration test (componenti insieme) dove appropriato.
        Copri casi principali e edge case.
        """
    }
}

/// Esegue i worker per ogni task del piano, usando qualsiasi LLMProvider
public struct SwarmWorkerRunner: Sendable {
    private let provider: any LLMProvider
    private let isCancelled: (@Sendable () -> Bool)?

    public init(provider: any LLMProvider, isCancelled: (@Sendable () -> Bool)? = nil) {
        self.provider = provider
        self.isCancelled = isCancelled
    }

    /// Esegue i task; task con stesso order vengono eseguiti in parallelo
    public func run(tasks: [AgentTask], context: WorkspaceContext, imageURLs: [URL]? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        let checkCancelled = isCancelled
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.started)
                    let sortedTasks = tasks.sorted(by: { $0.order < $1.order })
                    let stepNames = sortedTasks.map { $0.role.displayName }.joined(separator: ",")
                    continuation.yield(.raw(type: "swarm_steps", payload: ["steps": stepNames]))
                    var accumulatedOutput = ""

                    let orderGroups = Dictionary(grouping: sortedTasks, by: { $0.order }).sorted(by: { $0.key < $1.key })
                    var isFirstTask = true

                    for (_, groupTasks) in orderGroups {
                        if checkCancelled?() == true {
                            continuation.yield(.textDelta("\n\n[Swarm interrotto dall'utente.]\n"))
                            break
                        }
                        if groupTasks.count == 1 {
                            let task = groupTasks[0]
                            let header = "\n## \(task.role.displayName)\n\n"
                            continuation.yield(.textDelta(header))
                            continuation.yield(.raw(type: "agent", payload: swarmPayload(for: task, detail: "started")))
                            let taskImageURLs = isFirstTask && !(imageURLs?.isEmpty ?? true) ? imageURLs : nil
                            let output = try await runSingleTask(task, context: context, imageURLs: taskImageURLs, previousOutputs: accumulatedOutput, provider: provider, continuation: continuation)
                            continuation.yield(.raw(type: "agent", payload: swarmPayload(for: task, detail: "completed")))
                            accumulatedOutput += output + "\n"
                        } else {
                            continuation.yield(.textDelta("\n## Parallelo: \(groupTasks.map { $0.role.displayName }.joined(separator: ", "))\n\n"))
                            for t in groupTasks { continuation.yield(.raw(type: "agent", payload: swarmPayload(for: t, detail: "started"))) }
                            var groupOutputs: [(String, String)] = []
                            await withTaskGroup(of: (String, String).self) { g in
                                for (idx, task) in groupTasks.enumerated() {
                                    g.addTask {
                                        if checkCancelled?() == true {
                                            return (task.role.rawValue, "\n### \(task.role.displayName)\n\n[Interrotto dall'utente]\n")
                                        }
                                        let header = "\n### \(task.role.displayName)\n\n"
                                        let prompt = self.buildPrompt(for: task, previousOutputs: accumulatedOutput)
                                        let taskImageURLs = (isFirstTask && idx == 0 && !(imageURLs?.isEmpty ?? true)) ? imageURLs : nil
                                        var out = header
                                        var err: String?
                                        do {
                                            let stream = try await self.provider.send(prompt: prompt, context: context, imageURLs: taskImageURLs)
                                            for try await event in stream {
                                                if case .textDelta(let d) = event { out += d }
                                                if case .error(let e) = event { err = "\n[Errore \(task.role.displayName): \(e)]\n"; out += err! }
                                                if case .raw(let type, let payload) = event {
                                                    continuation.yield(.raw(type: type, payload: self.enrichSwarmPayload(payload, for: task)))
                                                }
                                            }
                                        } catch {
                                            err = "\n[Errore \(task.role.displayName): \(error.localizedDescription)]\n"
                                            out += err!
                                        }
                                        return (task.role.rawValue, out)
                                    }
                                }
                                for await res in g { groupOutputs.append(res) }
                            }
                            for t in groupTasks { continuation.yield(.raw(type: "agent", payload: swarmPayload(for: t, detail: "completed"))) }
                            let merged = groupOutputs.sorted(by: { $0.0 < $1.0 }).map(\.1).joined(separator: "\n")
                            continuation.yield(.textDelta(merged))
                            accumulatedOutput += merged + "\n"
                        }
                        if checkCancelled?() == true {
                            continuation.yield(.textDelta("\n\n[Swarm interrotto durante esecuzione parallela.]\n"))
                            break
                        }
                        isFirstTask = false
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runSingleTask(_ task: AgentTask, context: WorkspaceContext, imageURLs: [URL]?, previousOutputs: String, provider: any LLMProvider, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws -> String {
        let header = "\n## \(task.role.displayName)\n\n"
        let prompt = buildPrompt(for: task, previousOutputs: previousOutputs)
        var taskOutput = header
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                continuation.yield(.textDelta(delta))
                taskOutput += delta
            case .error(let err):
                let e = "\n[Errore \(task.role.displayName): \(err)]\n"
                continuation.yield(.textDelta(e))
                taskOutput += e
            case .raw(let type, let payload):
                continuation.yield(.raw(type: type, payload: enrichSwarmPayload(payload, for: task)))
            default: break
            }
        }
        return taskOutput
    }

    private func swarmPayload(for task: AgentTask, detail: String) -> [String: String] {
        [
            "title": task.role.displayName,
            "detail": detail,
            "swarm_id": task.role.rawValue,
            "group_id": "swarm-\(task.role.rawValue)"
        ]
    }

    private func enrichSwarmPayload(_ payload: [String: String], for task: AgentTask) -> [String: String] {
        var enriched = payload
        enriched["swarm_id"] = task.role.rawValue
        if enriched["group_id"] == nil {
            enriched["group_id"] = "swarm-\(task.role.rawValue)"
        }
        if (enriched["title"] ?? "").isEmpty {
            enriched["title"] = task.role.displayName
        }
        return enriched
    }

    private func buildPrompt(for task: AgentTask, previousOutputs: String) -> String {
        var parts: [String] = []
        parts.append(systemPrompt(for: task.role))
        parts.append("\n**Task:** \(task.taskDescription)")
        if !previousOutputs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\n**Output degli agenti precedenti:**\n\(previousOutputs)")
        }
        parts.append("\nEsegui il task. Rispondi e agisci nel workspace.")
        parts.append("\nSe vuoi mostrare all'utente il pannello delle attività in corso, includi nella risposta: \(CoderIDEMarkers.showTaskPanel)")

        parts.append("""

        **Multi-agent:** Se il task è complesso, usa i tuoi strumenti multi-agent interni \
        (subagent, Task tool, parallel execution) per scomporlo e risolverlo in parallelo. \
        Rispetta le istruzioni in AGENTS.md / CLAUDE.md se presenti nel workspace.
        """)
        return parts.joined()
    }
}
