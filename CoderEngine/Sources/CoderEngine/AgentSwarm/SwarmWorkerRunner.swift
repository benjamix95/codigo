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

/// Esegue i worker Codex per ogni task del piano
public struct SwarmWorkerRunner: Sendable {
    private let codexProvider: CodexCLIProvider

    public init(codexProvider: CodexCLIProvider) {
        self.codexProvider = codexProvider
    }

    /// Esegue i task in sequenza e streama l'output aggregato
    public func run(tasks: [AgentTask], context: WorkspaceContext) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.started)
                    let sortedTasks = tasks.sorted(by: { $0.order < $1.order })
                    let stepNames = sortedTasks.map { $0.role.displayName }.joined(separator: ",")
                    continuation.yield(.raw(type: "swarm_steps", payload: ["steps": stepNames]))
                    var accumulatedOutput = ""

                    for task in sortedTasks {
                        let header = "\n## \(task.role.displayName)\n\n"
                        continuation.yield(.textDelta(header))
                        continuation.yield(.raw(type: "agent", payload: ["title": task.role.displayName, "detail": "started"]))

                        let prompt = buildPrompt(for: task, previousOutputs: accumulatedOutput)
                        let stream = try await codexProvider.send(prompt: prompt, context: context)

                        var taskOutput = header
                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                continuation.yield(.textDelta(delta))
                                taskOutput += delta
                            case .completed, .started:
                                break
                            case .error(let err):
                                let errMsg = "\n[Errore \(task.role.displayName): \(err)]\n"
                                continuation.yield(.textDelta(errMsg))
                                taskOutput += errMsg
                            case .raw(let type, let payload):
                                continuation.yield(.raw(type: type, payload: payload))
                            }
                        }
                        continuation.yield(.raw(type: "agent", payload: ["title": task.role.displayName, "detail": "completed"]))
                        accumulatedOutput += taskOutput + "\n"
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

    private func buildPrompt(for task: AgentTask, previousOutputs: String) -> String {
        var parts: [String] = []
        parts.append(systemPrompt(for: task.role))
        parts.append("\n**Task:** \(task.taskDescription)")
        if !previousOutputs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\n**Output degli agenti precedenti:**\n\(previousOutputs)")
        }
        parts.append("\nEsegui il task. Rispondi e agisci nel workspace.")
        parts.append("\nSe vuoi mostrare all'utente il pannello delle attività in corso, includi nella risposta: \(CoderIDEMarkers.showTaskPanel)")
        return parts.joined()
    }
}
