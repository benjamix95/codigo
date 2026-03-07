import CoderEngine
import Foundation

// MARK: - Review Execution

extension CodeReviewPanelStore {

    /// Start an independent code review. Replicates the bootstrap deferred command pattern.
    func startReview(
        scope: ReviewScopeTarget,
        mode: CodeReviewPanelMode
    ) async {
        guard !isRunning else { return }

        lastError = nil
        isRunning = true
        runStartedAt = Date()
        frozenTimerText = nil

        let sessionId = generateSessionId()
        let sessionConfig = buildSessionConfig()

        let sessionState = CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: sessionConfig,
            onStateChange: { [weak self] snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self?.taskActivityStore.ingestCodeReviewSnapshot(
                        snapshot, conversationId: self?.conversationId
                    )
                    self?.panelSessionId = snapshot.sessionId
                }
            }
        )

        await ReviewSessionRegistry.shared.register(sessionState)

        let config = providerFactoryConfigBuilder()
        guard let provider = ProviderFactory.codeReviewMultiSwarmProvider(
            config: config,
            executionController: executionController,
            agentProviderId: providerRegistry.selectedProviderId,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths,
            sessionState: sessionState,
            initialSessionConfig: sessionConfig
        ) else {
            isRunning = false
            lastError = "Failed to create review provider"
            freezeTimer()
            return
        }

        let prompt = buildPrompt(scope: scope, mode: mode)
        let context = buildWorkspaceContext()

        panelSessionId = sessionId
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)

        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            onStart: { [weak self] in
                self?.selectedTab = .findings
            },
            onComplete: { [weak self] _ in
                self?.isRunning = false
                self?.freezeTimer()
            },
            onError: { [weak self] error in
                self?.isRunning = false
                self?.lastError = error
                self?.freezeTimer()
            }
        )
    }

    /// Cancel the current running review.
    func cancelReview() {
        coordinator.cancelReview()
        isRunning = false
        freezeTimer()
    }

    /// Re-run a review session with the same scope.
    func rerunSession(_ sessionId: String) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId, conversationId: conversationId
        ) else { return }

        let scope: ReviewScopeTarget
        switch snapshot.scope?.type {
        case .againstRef:
            scope = .againstRef(snapshot.scope?.ref ?? "HEAD~1")
        case .staged:
            scope = .staged
        case .uncommitted, .none:
            scope = .uncommitted
        }

        await startReview(scope: scope, mode: activeMode)
    }

    // MARK: - Finding Mutations

    func applyFix(sessionId: String, findingId: String) async {
        if let liveState = await ReviewSessionRegistry.shared.state(
            sessionId: sessionId
        ) {
            let succeeded = await liveState.applyFix(findingId: findingId)
            if succeeded {
                let snapshot = await liveState.snapshot()
                await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                taskActivityStore.ingestCodeReviewSnapshot(
                    snapshot, conversationId: conversationId
                )
            }
            return
        }
        await mutateSnapshot(sessionId: sessionId, findingId: findingId) { finding in
            finding.status = .fixApplied
        } event: {
            .findingFixApplied(findingId: findingId)
        }
    }

    func dismissFinding(
        sessionId: String,
        findingId: String,
        reason: String
    ) async {
        if let liveState = await ReviewSessionRegistry.shared.state(
            sessionId: sessionId
        ) {
            _ = await liveState.dismissFinding(findingId: findingId, reason: reason)
            let snapshot = await liveState.snapshot()
            await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
            taskActivityStore.ingestCodeReviewSnapshot(
                snapshot, conversationId: conversationId
            )
            return
        }
        let status: FindingStatus = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == FindingStatus.wontFix.rawValue ? .wontFix : .dismissed
        await mutateSnapshot(sessionId: sessionId, findingId: findingId) { finding in
            finding.status = status
        } event: {
            .findingDismissed(findingId: findingId, reason: reason)
        }
    }

    func applyAllFixes(sessionId: String, findingIds: [String]) async {
        for fid in findingIds {
            await applyFix(sessionId: sessionId, findingId: fid)
        }
    }

    func dismissAll(
        sessionId: String,
        findingIds: [String],
        reason: String
    ) async {
        for fid in findingIds {
            await dismissFinding(
                sessionId: sessionId, findingId: fid, reason: reason
            )
        }
    }

    // MARK: - Export

    func exportSummary(sessionId: String) -> String {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId, conversationId: conversationId
        ) else { return "No session found" }

        let header = """
        ## Code Review Summary
        - session_id: \(snapshot.sessionId)
        - phase: \(snapshot.phase.rawValue)
        - stage: \(snapshot.stage.rawValue)
        - scope: \(snapshot.scope?.description ?? "unknown")
        - findings: \(snapshot.findings.count)
        """

        let findings = snapshot.findings.map { finding in
            let line = finding.lineNumber.map { ":\($0)" } ?? ""
            return "- [\(finding.severity.rawValue)] \(finding.filePath)\(line) — \(finding.message)"
        }

        return ([header] + findings).joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func buildSessionConfig() -> SessionConfig {
        SessionConfig(
            maxWorkers: settings.maxWorkers,
            maxRounds: settings.maxRounds,
            analysisBackend: settings.analysisBackend,
            executionBackend: settings.executionBackend,
            analysisOnly: settings.analysisOnly
        )
    }

    private func buildPrompt(
        scope: ReviewScopeTarget,
        mode: CodeReviewPanelMode
    ) -> String {
        switch mode {
        case .standard:
            if case .commits(let commits) = scope, !commits.isEmpty {
                return ReviewPanelCoordinator.commitRangePrompt(commits: commits)
            }
            return ReviewPanelCoordinator.standardPrompt(
                scope: scope,
                customInstructions: settings.customInstructions
            )
        case .securityAudit:
            return ReviewPanelCoordinator.securityAuditPrompt(scope: scope)
        case .bugFinder:
            return ReviewPanelCoordinator.bugFinderPrompt(scope: scope)
        case .branchReview:
            if case .branch(let name) = scope {
                return ReviewPanelCoordinator.branchReviewPrompt(
                    branch: name, currentBranch: currentGitBranch
                )
            }
            return ReviewPanelCoordinator.standardPrompt(scope: scope)
        }
    }

    private func generateSessionId() -> String {
        let prefix = activeMode == .standard ? "panel" : activeMode.rawValue
            .lowercased().replacingOccurrences(of: " ", with: "-")
        return "\(prefix)-\(UUID().uuidString.lowercased().prefix(12))"
    }

    private func freezeTimer() {
        guard let start = runStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        frozenTimerText = String(format: "%d:%02d", minutes, seconds)
    }

    private func mutateSnapshot(
        sessionId: String,
        findingId: String,
        mutate: (inout CodeReviewFinding) -> Void,
        event: () -> CodeReviewSessionEvent
    ) async {
        // Fallback mutation for snapshots without live state
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId, conversationId: conversationId
        ) else { return }

        var findings = snapshot.findings
        guard let index = findings.firstIndex(where: { $0.id == findingId }) else { return }
        mutate(&findings[index])
        // Re-ingest the mutated snapshot
        let updated = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: findings,
            events: snapshot.events + [event()],
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            lastUpdatedAt: Date()
        )
        taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: conversationId)
    }
}
