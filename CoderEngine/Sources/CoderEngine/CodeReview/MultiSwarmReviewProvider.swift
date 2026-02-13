import Foundation

private let reviewAnalysisPrompt = """
Esegui una code review completa della porzione di codice fornita. Analizza:
- Bug e potenziali errori
- Warning e problemi di stile
- Ottimizzazioni possibili
- Sicurezza e dipendenze
- Best practice e manutenzione
Produci un report strutturato con priorità (alto/medio/basso) per ogni finding.
"""

private func scopedContext(base: WorkspaceContext, partition: CodebasePartition) -> WorkspaceContext {
    guard !partition.paths.isEmpty else {
        return WorkspaceContext(
            workspacePaths: base.workspacePaths,
            excludedPaths: base.excludedPaths,
            includedPaths: partition.paths,
            openFiles: []
        )
    }
    let basePath = base.workspacePath
    var openFiles: [OpenFile] = []
    for relPath in partition.paths.prefix(50) {
        let fullURL = basePath.appendingPathComponent(relPath)
        if let content = try? String(contentsOf: fullURL, encoding: .utf8) {
            openFiles.append(OpenFile(path: relPath, content: content))
        }
    }
    return WorkspaceContext(
        workspacePaths: base.workspacePaths,
        excludedPaths: base.excludedPaths,
        includedPaths: partition.paths,
        openFiles: openFiles
    )
}

private let reviewExecutionPrompt = """
In base al report di code review precedente, applica le correzioni necessarie a questa porzione di codice.
Modifica solo i file nella tua partizione. Correggi bug, warning, e migliora il codice dove indicato.
"""

/// Parametri per creare Codex CLI (usato per istanza con yolo in fase esecuzione)
public struct CodexCreateParams: Sendable {
    public let codexPath: String?
    public let sandboxMode: CodexSandboxMode
    public let modelOverride: String?
    public let modelReasoningEffort: String?

    public init(codexPath: String? = nil, sandboxMode: CodexSandboxMode = .workspaceWrite, modelOverride: String? = nil, modelReasoningEffort: String? = nil) {
        self.codexPath = codexPath
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride
        self.modelReasoningEffort = modelReasoningEffort
    }
}

/// Provider LLM per Code Review multi-swarm
public final class MultiSwarmReviewProvider: LLMProvider, @unchecked Sendable {
    public let id = "multi-swarm-review"
    public let displayName = "Code Review Multi-Swarm"

    private let config: MultiSwarmReviewConfig
    private let codexProvider: CodexCLIProvider
    private let codexParams: CodexCreateParams?

    public init(config: MultiSwarmReviewConfig, codexProvider: CodexCLIProvider, codexParams: CodexCreateParams? = nil) {
        self.config = config
        self.codexProvider = codexProvider
        self.codexParams = codexParams
    }

    public func isAuthenticated() -> Bool {
        codexProvider.isAuthenticated()
    }

    public func send(prompt: String, context: WorkspaceContext) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let codexProvider = self.codexProvider

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.started)
                    let partitions = CodebasePartitioner.partition(
                        workspacePath: context.workspacePath,
                        count: config.partitionCount,
                        strategy: .directory,
                        excludedPaths: context.excludedPaths
                    ).filter { !$0.paths.isEmpty }

                    if partitions.isEmpty {
                        continuation.yield(.textDelta("Nessun file sorgente trovato nel workspace."))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.textDelta("\n## Fase 1: Analisi multi-swarm\n\n"))
                    continuation.yield(.textDelta("Partizioni: \(partitions.count) (totale \(partitions.flatMap(\.paths).count) file)\n\n"))

                    var reports: [(partitionId: String, output: String)] = []

                    await withTaskGroup(of: (String, String).self) { group in
                        for p in partitions {
                            group.addTask {
                                let scoped = scopedContext(base: context, partition: p)
                                let reviewPrompt = "\(reviewAnalysisPrompt)\n\nPartizione \(p.id) - file: \(p.paths.prefix(10).joined(separator: ", "))\(p.paths.count > 10 ? "..." : "")"
                                var output = ""
                                do {
                                    let stream = try await codexProvider.send(prompt: reviewPrompt, context: scoped)
                                    for try await event in stream {
                                        if case .textDelta(let delta) = event {
                                            output += delta
                                        }
                                    }
                                } catch {
                                    output = "[Errore \(p.id): \(error.localizedDescription)]"
                                }
                                return (p.id, output)
                            }
                        }
                        for await result in group {
                            reports.append(result)
                        }
                    }

                    for (pid, output) in reports.sorted(by: { $0.partitionId < $1.partitionId }) {
                        continuation.yield(.textDelta("\n### Swarm \(pid)\n\n"))
                        continuation.yield(.textDelta(output))
                        continuation.yield(.textDelta("\n\n"))
                    }

                    let runPhase2 = config.enabledPhases == .analysisAndExecution && (config.yoloMode || prompt.lowercased().contains("procedi") || prompt.lowercased().contains("applica") || prompt.lowercased().contains("sì"))

                    if !runPhase2 {
                        continuation.yield(.textDelta("\n---\n**Analisi completata.** Per applicare le correzioni, invia un nuovo messaggio con \"procedi con le correzioni\" (o abilita modalità --yolo nelle impostazioni).\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.textDelta("\n## Fase 2: Esecuzione correzioni\n\n"))

                    let coordinator = FileLockCoordinator()
                    let claims = partitions.map { (id: $0.id, files: Set($0.paths)) }
                    let steps = await coordinator.planExecution(swarmFileClaims: claims.map { ($0.id, $0.files) })

                    let execCodex: CodexCLIProvider
                    if config.yoloMode, let p = codexParams {
                        execCodex = CodexCLIProvider(
                            codexPath: p.codexPath,
                            sandboxMode: p.sandboxMode,
                            modelOverride: p.modelOverride,
                            modelReasoningEffort: p.modelReasoningEffort,
                            yoloMode: true
                        )
                    } else {
                        execCodex = codexProvider
                    }

                    for step in steps {
                        guard let partition = partitions.first(where: { $0.id == step.swarmId }) else { continue }
                        await coordinator.acquireLock(files: step.files, swarmId: step.swarmId)
                        continuation.yield(.textDelta("\n### Swarm \(step.swarmId) - modifiche\n\n"))

                        let scoped = scopedContext(base: context, partition: partition)
                        let execPrompt = "\(reviewExecutionPrompt)\n\nFile nella partizione: \(partition.paths.joined(separator: ", "))"
                        do {
                            let stream = try await execCodex.send(prompt: execPrompt, context: scoped)
                            for try await event in stream {
                                continuation.yield(event)
                            }
                        } catch {
                            continuation.yield(.textDelta("[Errore: \(error.localizedDescription)]\n"))
                        }
                        await coordinator.releaseLock(files: step.files, swarmId: step.swarmId)
                    }

                    continuation.yield(.textDelta("\n\n**Correzioni completate.**\n"))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
