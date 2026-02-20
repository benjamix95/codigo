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
    public let askForApproval: String?

    public init(codexPath: String? = nil, sandboxMode: CodexSandboxMode = .workspaceWrite, modelOverride: String? = nil, modelReasoningEffort: String? = nil, askForApproval: String? = nil) {
        self.codexPath = codexPath
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride
        self.modelReasoningEffort = modelReasoningEffort
        self.askForApproval = CodexCLIProvider.normalizeAskForApproval(askForApproval)
    }
}

private let analysisClaudeTools = ["Read", "Glob", "Grep"]
private let missingWorkerOutputPrefix = "[Nessun output dal worker "

private enum ReviewFailureReason: String {
    case auth
    case timeout
    case cliExit = "cli_exit"
    case emptyOutput = "empty_output"
    case unknown
}

/// Provider LLM per Code Review multi-swarm
public final class MultiSwarmReviewProvider: LLMProvider, @unchecked Sendable {
    public let id = "multi-swarm-review"
    public let displayName = "Code Review Multi-Swarm"

    private let config: MultiSwarmReviewConfig
    private let codexProvider: CodexCLIProvider
    private let codexParams: CodexCreateParams?
    private let claudeProvider: ClaudeCLIProvider?
    /// Provider per Fase 2 (esecuzione correzioni): può essere Codex, Claude CLI o API con tools
    private let executionProvider: (any LLMProvider)?

    public init(
        config: MultiSwarmReviewConfig,
        codexProvider: CodexCLIProvider,
        codexParams: CodexCreateParams? = nil,
        claudeProvider: ClaudeCLIProvider? = nil,
        executionProvider: (any LLMProvider)? = nil
    ) {
        self.config = config
        self.codexProvider = codexProvider
        self.codexParams = codexParams
        self.claudeProvider = claudeProvider
        self.executionProvider = executionProvider
    }

    public func isAuthenticated() -> Bool {
        if config.analysisBackend == "claude", let claude = claudeProvider {
            return claude.isAuthenticated()
        }
        return codexProvider.isAuthenticated()
    }

    private func isMissingWorkerOutput(_ output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(missingWorkerOutputPrefix)
    }

    private func isFailedReport(_ output: String) -> Bool {
        failureReason(for: output) != nil
    }

    private func failureReason(for output: String) -> ReviewFailureReason? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyOutput }
        if isMissingWorkerOutput(trimmed) { return .emptyOutput }
        if trimmed.contains("non autenticat") { return .auth }
        if trimmed.localizedCaseInsensitiveContains("timeout") { return .timeout }
        if trimmed.contains("exit code") || trimmed.contains("[Errore") { return .cliExit }
        return nil
    }

    /// Esegue Fase 1 e invoca yieldPartition per ogni partizione non appena termina (streaming progressivo)
    private func runPhase1AnalysisStreaming(
        partitions: [CodebasePartition],
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        yieldPartition: @escaping (String, String) -> Void,
        yieldRaw: @escaping (StreamEvent) -> Void
    ) async -> [(partitionId: String, output: String)] {
        var reports: [(partitionId: String, output: String)] = []
        await withTaskGroup(of: (String, String).self) { group in
            for p in partitions {
                group.addTask {
                    let scoped = scopedContext(base: context, partition: p)
                    let reviewPrompt = "\(reviewAnalysisPrompt)\n\nPartizione \(p.id) - file: \(p.paths.prefix(10).joined(separator: ", "))\(p.paths.count > 10 ? "..." : "")"
                    var output = ""
                    yieldRaw(.raw(type: "agent", payload: ["title": "Swarm \(p.id)", "detail": "started"]))
                    yieldRaw(.raw(type: "read_batch_started", payload: [
                        "title": "Analisi partizione \(p.id) avviata",
                        "detail": "\(p.paths.count) file in scope",
                        "group_id": "review-\(p.id)"
                    ]))
                    do {
                        let stream = try await analysisProvider.send(prompt: reviewPrompt, context: scoped, imageURLs: nil)
                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                output += delta
                            case .raw:
                                yieldRaw(self.enrichRawEvent(event, swarmId: p.id))
                            default:
                                break
                            }
                        }
                    } catch {
                        output = "[Errore \(p.id): \(error.localizedDescription)]"
                        yieldRaw(.raw(type: "web_search_failed", payload: [
                            "title": "Errore analisi partizione \(p.id)",
                            "detail": error.localizedDescription,
                            "group_id": "review-\(p.id)"
                        ]))
                    }
                    if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output = "\(missingWorkerOutputPrefix)\(p.id). Verifica autenticazione provider o timeout.]"
                    }
                    yieldRaw(.raw(type: "read_batch_completed", payload: [
                        "title": "Analisi partizione \(p.id) completata",
                        "detail": "\(p.paths.count) file processati",
                        "group_id": "review-\(p.id)"
                    ]))
                    yieldRaw(.raw(type: "agent", payload: ["title": "Swarm \(p.id)", "detail": "completed"]))
                    return (p.id, output)
                }
            }
            for await result in group {
                reports.append(result)
                yieldPartition(result.0, result.1)
            }
        }
        return reports.sorted(by: { $0.partitionId < $1.partitionId })
    }

    private func hasSignificantFindings(_ reports: [(partitionId: String, output: String)]) -> Bool {
        let lowercased = reports.map { $0.output.lowercased().trimmingCharacters(in: .whitespaces) }
        let triggers = ["priorità alta", "priorità alta:", "bug", "correggere", "problema", "errore", "warning", "sicurezza", "vulnerabilità"]
        for o in lowercased {
            guard o.count > 50 else { continue }
            if triggers.contains(where: { o.contains($0) }) { return true }
        }
        return false
    }

    private func enrichRawEvent(_ event: StreamEvent, swarmId: String) -> StreamEvent {
        guard case .raw(let type, let payload) = event else { return event }
        var enriched = payload
        enriched["swarm_id"] = swarmId
        if enriched["group_id"] == nil {
            enriched["group_id"] = "swarm-\(swarmId)"
        }
        if (enriched["title"] ?? "").isEmpty {
            enriched["title"] = "Swarm \(swarmId)"
        }
        return .raw(type: type, payload: enriched)
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let codexProvider = self.codexProvider
        let codexParams = self.codexParams

        let analysisProvider: any LLMProvider
        if config.analysisBackend == "claude", claudeProvider != nil {
            analysisProvider = ClaudeCLIProvider(allowedTools: analysisClaudeTools, executionController: nil, executionScope: .review)
        } else if let p = codexParams {
            analysisProvider = CodexCLIProvider(
                codexPath: p.codexPath,
                sandboxMode: .readOnly,
                modelOverride: p.modelOverride,
                modelReasoningEffort: p.modelReasoningEffort,
                askForApproval: p.askForApproval,
                executionScope: .review
            )
        } else {
            analysisProvider = codexProvider
        }

        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                guard analysisProvider.isAuthenticated() else {
                    continuation.yield(.textDelta("**Analisi non avviata:** provider di analisi non autenticato. Verifica Codex CLI/Claude CLI nelle impostazioni.\n"))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let promptLower = prompt.lowercased()
                let useUncommitted = promptLower.contains("non committati") || promptLower.contains("uncommitted") || promptLower.contains("non committate") || promptLower.contains("modificati") || promptLower.contains("changed") || promptLower.contains("modified") || promptLower.contains("staged")
                let scope: FileScope = useUncommitted ? .uncommitted : .all
                let partitions = CodebasePartitioner.partition(
                    workspacePath: context.workspacePath,
                    count: config.partitionCount,
                    strategy: .directory,
                    excludedPaths: context.excludedPaths,
                    scope: scope
                ).filter { !$0.paths.isEmpty }

                if partitions.isEmpty {
                    let msg = scope == .uncommitted
                        ? "Nessun file sorgente non committato trovato (git status)."
                        : "Nessun file sorgente trovato nel workspace."
                    continuation.yield(.textDelta(msg))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let analysisBackendLabel = config.analysisBackend == "claude" ? "claude" : "codex"
                let execBackendLabel = config.executionBackend
                let totalFiles = partitions.flatMap(\.paths).count
                continuation.yield(.textDelta("\n## Diagnostica\n\n"))
                continuation.yield(.textDelta("- Provider analisi: `\(analysisBackendLabel)`\n"))
                if config.enabledPhases == .analysisAndExecution {
                    continuation.yield(.textDelta("- Provider esecuzione Fase 2: `\(execBackendLabel)`\n"))
                }
                continuation.yield(.textDelta("- Scope: `\(scope == .uncommitted ? "uncommitted" : "all")`\n"))
                continuation.yield(.textDelta("- Partizioni: `\(partitions.count)`\n"))
                continuation.yield(.textDelta("- File inclusi: `\(totalFiles)`\n"))
                if scope == .uncommitted {
                    let preview = Array(partitions.flatMap(\.paths).prefix(12))
                    if !preview.isEmpty {
                        continuation.yield(.textDelta("- Esempio file scope: `\(preview.joined(separator: "`, `"))`\n"))
                    }
                }
                continuation.yield(.textDelta("\n"))

                let runPhase2 = config.enabledPhases == .analysisAndExecution && (config.yoloMode || prompt.lowercased().contains("procedi") || prompt.lowercased().contains("applica") || prompt.lowercased().contains("sì"))

                let yieldPartition: (String, String) -> Void = { pid, output in
                    continuation.yield(.textDelta("\n### Swarm \(pid)\n\n"))
                    continuation.yield(.textDelta(output))
                    continuation.yield(.textDelta("\n\n"))
                }

                var reports: [(partitionId: String, output: String)] = []

                for round in 1...config.maxReviewRounds {
                    if round > 1 {
                        continuation.yield(.textDelta("\n## Iterazione \(round): Ri-analisi\n\n"))
                        reports = await runPhase1AnalysisStreaming(
                            partitions: partitions,
                            context: context,
                            analysisProvider: analysisProvider,
                            yieldPartition: yieldPartition,
                            yieldRaw: { continuation.yield($0) }
                        )
                    } else {
                        continuation.yield(.textDelta("\n## Fase 1: Analisi multi-swarm\n\n"))
                        if scope == .uncommitted {
                            continuation.yield(.textDelta("Scope: solo file non committati.\n\n"))
                        }
                        continuation.yield(.textDelta("Partizioni: \(partitions.count) (totale \(partitions.flatMap(\.paths).count) file)\n\n"))
                        continuation.yield(.textDelta("Avvio analisi in parallelo su \(partitions.count) swarm...\n\n"))
                        reports = await runPhase1AnalysisStreaming(
                            partitions: partitions,
                            context: context,
                            analysisProvider: analysisProvider,
                            yieldPartition: yieldPartition,
                            yieldRaw: { continuation.yield($0) }
                        )
                    }

                    let allFailed = reports.allSatisfy { isFailedReport($0.output) }
                    if allFailed && !reports.isEmpty {
                        var counters: [ReviewFailureReason: Int] = [:]
                        for report in reports {
                            if let reason = failureReason(for: report.output) {
                                counters[reason, default: 0] += 1
                            } else {
                                counters[.unknown, default: 0] += 1
                            }
                        }
                        let ordered: [ReviewFailureReason] = [.auth, .cliExit, .timeout, .emptyOutput, .unknown]
                        let diagnostic = ordered.compactMap { reason -> String? in
                            guard let count = counters[reason], count > 0 else { return nil }
                            return "- \(reason.rawValue): \(count)"
                        }.joined(separator: "\n")
                        continuation.yield(.textDelta("\n---\n**Analisi fallita su tutte le partizioni.** Cause aggregate:\n\(diagnostic)\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    if !runPhase2 {
                        if round == 1 {
                            continuation.yield(.textDelta("\n---\n**Analisi completata.** Per applicare le correzioni, invia un nuovo messaggio con \"procedi con le correzioni\" (o abilita modalità --yolo nelle impostazioni).\n"))
                        }
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    if round > 1 && !hasSignificantFindings(reports) {
                        continuation.yield(.textDelta("\n---\n**Nessun nuovo finding rilevante. Correzioni completate.**\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.textDelta("\n## Fase 2\(round > 1 ? " (iterazione \(round))" : ""): Esecuzione correzioni\n\n"))

                    let coordinator = FileLockCoordinator()
                    let steps = await coordinator.planExecution(swarmFileClaims: partitions.map { ($0.id, Set($0.paths)) })

                    let execProvider: any LLMProvider
                    if let custom = executionProvider {
                        execProvider = custom
                    } else {
                        let execCodex: CodexCLIProvider
                        if config.yoloMode, let p = codexParams {
                            execCodex = CodexCLIProvider(
                                codexPath: p.codexPath,
                                sandboxMode: p.sandboxMode,
                                modelOverride: p.modelOverride,
                                modelReasoningEffort: p.modelReasoningEffort,
                                yoloMode: true,
                                askForApproval: p.askForApproval,
                                executionScope: .review
                            )
                        } else {
                            execCodex = codexProvider
                        }
                        execProvider = execCodex
                    }

                    for step in steps {
                        guard let partition = partitions.first(where: { $0.id == step.swarmId }) else { continue }
                        await coordinator.acquireLock(files: step.files, swarmId: step.swarmId)
                        continuation.yield(.textDelta("\n### Swarm \(step.swarmId) - modifiche\n\n"))
                        continuation.yield(.raw(type: "agent", payload: [
                            "title": "Swarm \(step.swarmId)",
                            "detail": "started",
                            "swarm_id": step.swarmId
                        ]))

                        let scoped = scopedContext(base: context, partition: partition)
                        let execPrompt = "\(reviewExecutionPrompt)\n\nFile nella partizione: \(partition.paths.joined(separator: ", "))"
                        do {
                            let stream = try await execProvider.send(prompt: execPrompt, context: scoped, imageURLs: nil)
                            for try await event in stream {
                                continuation.yield(enrichRawEvent(event, swarmId: step.swarmId))
                            }
                            continuation.yield(.raw(type: "agent", payload: [
                                "title": "Swarm \(step.swarmId)",
                                "detail": "completed",
                                "swarm_id": step.swarmId
                            ]))
                        } catch {
                            let fullMsg = error.localizedDescription
                            let detailTruncated = String(fullMsg.prefix(2000))
                            let suggestions = [
                                "Prova con yolo mode nelle impostazioni Code Review",
                                "Verifica API key e autenticazione del provider (Codex CLI: `codex login status`, Claude CLI: configurazione)",
                                "Cambia backend esecuzione Fase 2 nelle impostazioni (es. Anthropic/OpenAI API applicano modifiche in-process senza subprocess)"
                            ].joined(separator: "; ")
                            continuation.yield(.textDelta("[Errore: \(fullMsg)]\n\n**Suggerimenti:** \(suggestions)\n"))
                            continuation.yield(.raw(type: "web_search_failed", payload: [
                                "title": "Swarm \(step.swarmId)",
                                "detail": "Errore in fase modifiche: \(detailTruncated)",
                                "swarm_id": step.swarmId,
                                "group_id": "swarm-\(step.swarmId)"
                            ]))
                        }
                        await coordinator.releaseLock(files: step.files, swarmId: step.swarmId)
                    }
                }

                continuation.yield(.textDelta("\n\n**Correzioni completate (\(config.maxReviewRounds) iterazioni max).**\n"))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
