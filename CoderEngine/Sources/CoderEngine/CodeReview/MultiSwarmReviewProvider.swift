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

private let reviewAreaOrchestratorPromptHeader = """
Sei un orchestratore di code review. Ricevi report multi-swarm e devi proporre aree di intervento (se utili).
Rispondi SOLO con JSON valido nel formato:
{
  "areas": [
    {
      "id": "area-1",
      "label": "nome area",
      "partitionIds": ["p0"],
      "fileHints": ["Sources/A.swift"],
      "severity": "alta|media|bassa",
      "highlights": ["riassunto finding"]
    }
  ],
  "summary": "sintesi globale"
}
Se non è utile segmentare in aree, restituisci areas = [] ma summary valorizzata.
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

private let missingWorkerOutputPrefix = "[Nessun output dal worker "

private enum ReviewFailureReason: String {
    case auth
    case timeout
    case cliExit = "cli_exit"
    case emptyOutput = "empty_output"
    case unknown
}

private struct ReviewAreaSummary: Codable, Sendable {
    let id: String
    let label: String
    let partitionIds: [String]
    let fileHints: [String]
    let severity: String
    let highlights: [String]
}

private struct ReviewAreaOrchestratorResult: Codable, Sendable {
    let areas: [ReviewAreaSummary]
    let summary: String
}

private struct ReviewSessionState: Sendable {
    let sessionId: String
    let workspaceKey: String
    let scope: FileScope
    let createdAt: Date
    let partitions: [CodebasePartition]
    let reportsByPartition: [String: String]
    let areas: [ReviewAreaSummary]
    var completedAreaIds: Set<String>
    var analysisCompleted: Bool
}

private enum AreaSelection {
    case all
    case area(String)
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
    /// Override opzionale del provider analisi/orchestrator (utile per test o wiring custom).
    private let analysisProviderOverride: (any LLMProvider)?

    private let stateLock = NSLock()
    private var sessionsByWorkspaceKey: [String: ReviewSessionState] = [:]
    private let sessionTTL: TimeInterval = 30 * 60

    public init(
        config: MultiSwarmReviewConfig,
        codexProvider: CodexCLIProvider,
        codexParams: CodexCreateParams? = nil,
        claudeProvider: ClaudeCLIProvider? = nil,
        executionProvider: (any LLMProvider)? = nil,
        analysisProviderOverride: (any LLMProvider)? = nil
    ) {
        self.config = config
        self.codexProvider = codexProvider
        self.codexParams = codexParams
        self.claudeProvider = claudeProvider
        self.executionProvider = executionProvider
        self.analysisProviderOverride = analysisProviderOverride
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

    private func workspaceKey(context: WorkspaceContext, scope: FileScope) -> String {
        "\(context.workspacePath.path)#\(scope == .uncommitted ? "uncommitted" : "all")"
    }

    private func cleanupExpiredSessions(now: Date = .now) {
        stateLock.lock()
        defer { stateLock.unlock() }
        sessionsByWorkspaceKey = sessionsByWorkspaceKey.filter { _, state in
            now.timeIntervalSince(state.createdAt) <= sessionTTL
        }
    }

    private func loadSession(for key: String) -> ReviewSessionState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sessionsByWorkspaceKey[key]
    }

    private func saveSession(_ state: ReviewSessionState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        sessionsByWorkspaceKey[state.workspaceKey] = state
    }

    private func removeSession(for key: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        sessionsByWorkspaceKey.removeValue(forKey: key)
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

    private func parsedText(from stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> String {
        var full = ""
        for try await event in stream {
            if case .textDelta(let delta) = event {
                full += delta
            }
        }
        return full
    }

    private func extractJSONBlock(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return trimmed }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            return String(trimmed[start...end])
        }
        return nil
    }

    private func severityForText(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("p0") || lower.contains("priorità alta") || lower.contains("vulnerabil") || lower.contains("critico") {
            return "alta"
        }
        if lower.contains("p1") || lower.contains("warning") || lower.contains("problema") {
            return "media"
        }
        return "bassa"
    }

    private func fallbackAreas(
        reports: [(partitionId: String, output: String)],
        partitionsById: [String: CodebasePartition]
    ) -> [ReviewAreaSummary] {
        var buckets: [String: (partitionIds: [String], fileHints: [String], highlights: [String], severity: String)] = [:]
        for report in reports {
            guard let partition = partitionsById[report.partitionId] else { continue }
            let root = partition.paths.first?.split(separator: "/").first.map(String.init) ?? "workspace"
            let key = root.isEmpty ? "workspace" : root
            var current = buckets[key] ?? ([], [], [], "bassa")
            current.partitionIds.append(report.partitionId)
            current.fileHints.append(contentsOf: partition.paths.prefix(5))
            current.highlights.append(String(report.output.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines))
            let sev = severityForText(report.output)
            if sev == "alta" || (sev == "media" && current.severity == "bassa") {
                current.severity = sev
            }
            buckets[key] = current
        }

        return buckets.keys.sorted().enumerated().map { idx, key in
            let b = buckets[key] ?? ([], [], [], "bassa")
            return ReviewAreaSummary(
                id: "area-\(idx + 1)",
                label: key,
                partitionIds: Array(Set(b.partitionIds)).sorted(),
                fileHints: Array(Set(b.fileHints)).sorted(),
                severity: b.severity,
                highlights: Array(b.highlights.prefix(3))
            )
        }
    }

    private func groupReportsByArea(
        reports: [(partitionId: String, output: String)],
        partitionsById: [String: CodebasePartition],
        provider: any LLMProvider,
        context: WorkspaceContext
    ) async -> ReviewAreaOrchestratorResult {
        let compactReports = reports.map { item in
            [
                "partitionId": item.partitionId,
                "report": String(item.output.prefix(4000)),
                "files": partitionsById[item.partitionId]?.paths.prefix(20).joined(separator: ", ") ?? ""
            ]
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: compactReports, options: [.fragmentsAllowed])
            let reportsJSON = String(data: data, encoding: .utf8) ?? "[]"
            let prompt = """
\(reviewAreaOrchestratorPromptHeader)

Report disponibili:\n\(reportsJSON)
"""
            let stream = try await provider.send(prompt: prompt, context: context, imageURLs: nil)
            let raw = try await parsedText(from: stream)
            if let json = extractJSONBlock(from: raw), let payload = json.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(ReviewAreaOrchestratorResult.self, from: payload)
                return decoded
            }
        } catch {
            // fallback sotto
        }

        let fallback = fallbackAreas(reports: reports, partitionsById: partitionsById)
        return ReviewAreaOrchestratorResult(
            areas: fallback,
            summary: "Raggruppamento fallback per directory principale (orchestrator non disponibile)."
        )
    }

    private func renderAreasMarkdown(_ areas: [ReviewAreaSummary], summary: String) -> String {
        var lines: [String] = []
        lines.append("## Raggruppamento aree (proposto dall'orchestrator)\n")
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\(summary)\n")
        }
        if areas.isEmpty {
            lines.append("Nessuna area separata necessaria: puoi procedere con i fix globali.\n")
            return lines.joined(separator: "\n")
        }

        for area in areas {
            lines.append("### \(area.id) • \(area.label) [\(area.severity)]")
            if !area.partitionIds.isEmpty {
                lines.append("- Partizioni: `\(area.partitionIds.joined(separator: "`, `"))`")
            }
            if !area.fileHints.isEmpty {
                lines.append("- File hint: `\(area.fileHints.prefix(6).joined(separator: "`, `"))`")
            }
            for h in area.highlights.prefix(2) where !h.isEmpty {
                lines.append("- Finding: \(h)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func parseAreaSelection(_ prompt: String) -> AreaSelection? {
        let n = normalized(prompt)
        if n.contains("focus tutte") || n.contains("focus all") || n.contains("procedi fix") || n.contains("procedi con i fix") || n.contains("applica fix") {
            return .all
        }

        let pattern = #"focus\s+area\s+(?:area-)?([0-9]+|[a-z0-9\-_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(n.startIndex..<n.endIndex, in: n)
        guard let match = regex.firstMatch(in: n, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: n) else { return nil }
        let raw = String(n[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if Int(raw) != nil {
            return .area("area-\(raw)")
        }
        return .area(raw.hasPrefix("area-") ? raw : "area-\(raw)")
    }

    private func executionProviderForPhase2() -> any LLMProvider {
        if let custom = executionProvider {
            return custom
        }

        if config.yoloMode, let p = codexParams {
            return CodexCLIProvider(
                codexPath: p.codexPath,
                sandboxMode: p.sandboxMode,
                modelOverride: p.modelOverride,
                modelReasoningEffort: p.modelReasoningEffort,
                yoloMode: true,
                askForApproval: p.askForApproval,
                executionScope: .review
            )
        }

        return codexProvider
    }

    private func runPhase2ForPartitions(
        selectedPartitions: [CodebasePartition],
        context: WorkspaceContext,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        guard !selectedPartitions.isEmpty else { return }

        let coordinator = FileLockCoordinator()
        let steps = await coordinator.planExecution(
            swarmFileClaims: selectedPartitions.map { ($0.id, Set($0.paths)) }
        )

        let execProvider = executionProviderForPhase2()
        for step in steps {
            guard let partition = selectedPartitions.first(where: { $0.id == step.swarmId }) else { continue }
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
                continuation.yield(.textDelta("[Errore: \(fullMsg)]\n"))
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

    private func selectionPrompt(for state: ReviewSessionState) -> String {
        if state.areas.isEmpty {
            return "\n---\nScrivi `focus tutte` (oppure `procedi fix`) per applicare i fix globali.\n"
        }

        let remaining = state.areas.filter { !state.completedAreaIds.contains($0.id) }
        if remaining.isEmpty {
            return "\n---\nNessuna area residua: puoi usare `focus tutte` per eventuali fix globali finali.\n"
        }

        let lines = remaining.map { "- `\($0.id)` • \($0.label) [\($0.severity)]" }.joined(separator: "\n")
        return """
\n---
Seleziona il focus fix:
\(lines)

Comandi supportati:
- `focus area <id>`
- `focus tutte`
"""
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let codexProvider = self.codexProvider
        let codexParams = self.codexParams

        let analysisProvider: any LLMProvider
        if let override = analysisProviderOverride {
            analysisProvider = override
        } else if config.analysisBackend == "claude", let claude = claudeProvider {
            analysisProvider = claude
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
                cleanupExpiredSessions()

                guard analysisProvider.isAuthenticated() else {
                    continuation.yield(.textDelta("**Analisi non avviata:** provider di analisi non autenticato. Verifica Codex CLI/Claude CLI nelle impostazioni.\n"))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let promptLower = normalized(prompt)
                let useUncommitted = promptLower.contains("non committati") || promptLower.contains("uncommitted") || promptLower.contains("non committate") || promptLower.contains("modificati") || promptLower.contains("changed") || promptLower.contains("modified") || promptLower.contains("staged")
                let scope: FileScope = useUncommitted ? .uncommitted : .all
                let wsKey = workspaceKey(context: context, scope: scope)

                if let selection = parseAreaSelection(prompt),
                   let session = loadSession(for: wsKey),
                   session.analysisCompleted,
                   config.enabledPhases == .analysisAndExecution
                {
                    let remainingAreas = session.areas.filter { !session.completedAreaIds.contains($0.id) }
                    let selectedAreaIds: Set<String>
                    switch selection {
                    case .all:
                        selectedAreaIds = Set(remainingAreas.map(\.id))
                    case .area(let id):
                        let resolved = remainingAreas.first { $0.id == id }
                        guard let resolved else {
                            continuation.yield(.textDelta("Area `\(id)` non trovata.\n" + selectionPrompt(for: session)))
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }
                        selectedAreaIds = [resolved.id]
                    }

                    let selectedPartitionsIds: Set<String>
                    if selectedAreaIds.isEmpty {
                        selectedPartitionsIds = Set(session.partitions.map(\.id))
                    } else {
                        selectedPartitionsIds = Set(session.areas
                            .filter { selectedAreaIds.contains($0.id) }
                            .flatMap(\.partitionIds))
                    }

                    let selectedPartitions = session.partitions.filter { selectedPartitionsIds.contains($0.id) }
                    continuation.yield(.raw(type: "review_area_selection_applied", payload: [
                        "title": "Area selection applied",
                        "detail": selectedAreaIds.isEmpty ? "all" : selectedAreaIds.sorted().joined(separator: ","),
                        "group_id": "review-area"
                    ]))
                    continuation.yield(.textDelta("\n## Fase 2: Esecuzione correzioni\n\n"))
                    await runPhase2ForPartitions(selectedPartitions: selectedPartitions, context: context, continuation: continuation)

                    var next = session
                    if selectedAreaIds.isEmpty {
                        next.completedAreaIds.formUnion(next.areas.map(\.id))
                    } else {
                        next.completedAreaIds.formUnion(selectedAreaIds)
                    }

                    let residual = next.areas.filter { !next.completedAreaIds.contains($0.id) }
                    for area in next.areas where next.completedAreaIds.contains(area.id) {
                        continuation.yield(.raw(type: "review_area_completed", payload: [
                            "title": "Area completata",
                            "detail": "\(area.id) • \(area.label)",
                            "group_id": "review-area"
                        ]))
                    }

                    if residual.isEmpty || selectedAreaIds.isEmpty {
                        removeSession(for: wsKey)
                        continuation.yield(.textDelta("\n\n**Correzioni completate.**\n"))
                    } else {
                        saveSession(next)
                        continuation.yield(.textDelta("\n\n**Area completata.** Restano \(residual.count) aree.\n"))
                        continuation.yield(.raw(type: "review_area_selection_requested", payload: [
                            "title": "Nuova selezione area richiesta",
                            "detail": "Aree residue: \(residual.map(\.id).joined(separator: ", "))",
                            "group_id": "review-area"
                        ]))
                        continuation.yield(.textDelta(selectionPrompt(for: next)))
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                if parseAreaSelection(prompt) != nil,
                   loadSession(for: wsKey) == nil,
                   config.enabledPhases == .analysisAndExecution
                {
                    continuation.yield(.textDelta("Nessuna sessione review attiva per questa cartella. Esegui prima una nuova analisi multi-swarm.\n"))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

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
                let totalFiles = partitions.flatMap(\.paths).count
                continuation.yield(.textDelta("\n## Diagnostica\n\n"))
                continuation.yield(.textDelta("- Provider analisi/orchestrator: `\(analysisBackendLabel)`\n"))
                if config.enabledPhases == .analysisAndExecution {
                    continuation.yield(.textDelta("- Provider esecuzione Fase 2: `\(config.executionBackend)`\n"))
                }
                continuation.yield(.textDelta("- Scope: `\(scope == .uncommitted ? "uncommitted" : "all")`\n"))
                continuation.yield(.textDelta("- Partizioni: `\(partitions.count)`\n"))
                continuation.yield(.textDelta("- File inclusi: `\(totalFiles)`\n\n"))

                continuation.yield(.textDelta("\n## Fase 1: Analisi multi-swarm\n\n"))
                continuation.yield(.textDelta("Avvio analisi in parallelo su \(partitions.count) swarm...\n\n"))

                let reports = await runPhase1AnalysisStreaming(
                    partitions: partitions,
                    context: context,
                    analysisProvider: analysisProvider,
                    yieldPartition: { pid, output in
                        continuation.yield(.textDelta("\n### Swarm \(pid)\n\n"))
                        continuation.yield(.textDelta(output))
                        continuation.yield(.textDelta("\n\n"))
                    },
                    yieldRaw: { continuation.yield($0) }
                )

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

                let partitionsById = Dictionary(uniqueKeysWithValues: partitions.map { ($0.id, $0) })
                let grouped = await groupReportsByArea(
                    reports: reports,
                    partitionsById: partitionsById,
                    provider: analysisProvider,
                    context: context
                )

                continuation.yield(.raw(type: "review_area_grouping_update", payload: [
                    "title": "Aree aggiornate",
                    "detail": "\(grouped.areas.count) aree",
                    "group_id": "review-area"
                ]))
                continuation.yield(.textDelta("\n" + renderAreasMarkdown(grouped.areas, summary: grouped.summary) + "\n"))

                if config.enabledPhases == .analysisOnly {
                    continuation.yield(.textDelta("\n---\n**Analisi completata (modalità solo analisi).**\n"))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let session = ReviewSessionState(
                    sessionId: UUID().uuidString,
                    workspaceKey: wsKey,
                    scope: scope,
                    createdAt: .now,
                    partitions: partitions,
                    reportsByPartition: Dictionary(uniqueKeysWithValues: reports.map { ($0.partitionId, $0.output) }),
                    areas: grouped.areas,
                    completedAreaIds: [],
                    analysisCompleted: true
                )
                saveSession(session)

                continuation.yield(.raw(type: "review_area_selection_requested", payload: [
                    "title": "Selezione area richiesta",
                    "detail": grouped.areas.isEmpty ? "no-areas" : grouped.areas.map(\.id).joined(separator: ","),
                    "group_id": "review-area"
                ]))
                continuation.yield(.textDelta(selectionPrompt(for: session)))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
