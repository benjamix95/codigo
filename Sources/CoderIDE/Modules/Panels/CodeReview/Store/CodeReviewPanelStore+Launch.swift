import CoderEngine
import Foundation

// MARK: - Review Execution

extension CodeReviewPanelStore {

    /// Start an independent code review. Replicates the bootstrap deferred command pattern.
    func startReview(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>,
        promptOverride: String? = nil,
        invocationLabel: String? = nil
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
            agentProviderId: effectivePanelProviderId,
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

        let prompt = promptOverride ?? buildPrompt(scope: scope, modes: modes)
        let context = buildWorkspaceContext()
        let reviewRunTitle = invocationLabel ?? reviewInvocationLabel(scope: scope, modes: modes)
        createNewChatThread(title: sessionId)
        let outputMessageId = beginPanelActionOutput(
            title: reviewRunTitle,
            detail: prompt,
            selectChatTab: true
        )
        appendReviewRunSectionLine(
            id: outputMessageId,
            sectionTitle: "Activity",
            line: "Preparing review pipeline..."
        )

        panelSessionId = sessionId
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)

        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            onEvent: { [weak self] event in
                self?.streamPanelActionOutput(id: outputMessageId, event: event)
            },
            onStart: { [weak self] in
                self?.selectedTab = .chat
            },
            onComplete: { [weak self] _ in
                self?.isRunning = false
                self?.freezeTimer()
                self?.finishPanelActionOutput(
                    id: outputMessageId,
                    fallbackContent: "Review completed."
                )
            },
            onError: { [weak self] error in
                self?.isRunning = false
                self?.lastError = error
                self?.freezeTimer()
                self?.failPanelActionOutput(id: outputMessageId, error: error)
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

        await startReview(scope: scope, modes: selectedModes)
    }

    func runQuickCommand(_ command: ReviewPanelSlashCommand) async {
        await startReview(
            scope: scopeTarget,
            modes: selectedModes,
            promptOverride: command.prompt,
            invocationLabel: command.displayCommand
        )
    }

    // MARK: - Finding Mutations

    func applyFix(sessionId: String, findingId: String) async {
        guard let sourceSnapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ), let finding = sourceSnapshot.findings.first(where: { $0.id == findingId }) else {
            return
        }

        let launched = await launchTargetedFixRun(
            sourceSnapshot: sourceSnapshot,
            findings: [finding]
        )
        if launched {
            return
        }

        await mutateSnapshot(sessionId: sessionId, findingId: findingId) { finding in
            finding.status = .fixApplied
        } event: {
            .findingFixApplied(findingId: findingId)
        }
        appendPanelSystemMessage(
            "Fix applied to finding \(findingId).",
            kind: .findingMutation,
            selectChatTab: false
        )
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
            appendPanelSystemMessage(
                "Finding \(findingId) dismissed (\(reason)).",
                kind: .findingMutation,
                selectChatTab: false
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
        appendPanelSystemMessage(
            "Finding \(findingId) dismissed (\(reason)).",
            kind: .findingMutation,
            selectChatTab: false
        )
    }

    func applyAllFixes(sessionId: String, findingIds: [String]) async {
        guard let sourceSnapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return
        }
        let findings = sourceSnapshot.findings.filter { findingIds.contains($0.id) }
        guard !findings.isEmpty else { return }

        let launched = await launchTargetedFixRun(
            sourceSnapshot: sourceSnapshot,
            findings: findings
        )
        if launched {
            return
        }

        for finding in findings {
            await applyFix(sessionId: sessionId, findingId: finding.id)
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

    // MARK: - Private Helpers

    private func buildSessionConfig() -> SessionConfig {
        let selectedBackend = selectedProviderOverrideId ?? ""
        return SessionConfig(
            maxWorkers: settings.maxWorkers,
            maxRounds: settings.maxRounds,
            analysisBackend: selectedBackend.isEmpty ? settings.analysisBackend : selectedBackend,
            executionBackend: selectedBackend.isEmpty ? settings.executionBackend : selectedBackend,
            analysisOnly: settings.analysisOnly
        )
    }

    private func buildPrompt(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>
    ) -> String {
        ReviewPanelCoordinator.combinedPrompt(
            scope: scope,
            currentBranch: currentGitBranch,
            selectedModes: modes,
            customInstructions: settings.customInstructions
        )
    }

    private func generateSessionId() -> String {
        let prefix: String = if selectedModes == [.standard] {
            "panel"
        } else {
            primarySelectedMode.rawValue
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }
        return "\(prefix)-\(UUID().uuidString.lowercased().prefix(12))"
    }

    private func freezeTimer() {
        guard let start = runStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        frozenTimerText = String(format: "%d:%02d", minutes, seconds)
    }

    private func reviewInvocationLabel(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>
    ) -> String {
        let label = CodeReviewPanelMode.allCases
            .filter { modes.contains($0) }
            .map(\.displayName)
            .joined(separator: " + ")
        return "Run \(label) on \(scope.displayDescription)"
    }

    private func launchTargetedFixRun(
        sourceSnapshot: CodeReviewSessionSnapshot,
        findings: [CodeReviewFinding]
    ) async -> Bool {
        let cfg = providerFactoryConfigBuilder()
        let sessionConfig = sourceSnapshot.config
        let fixSessionId = makePanelTargetedFixSessionId(sourceSessionId: sourceSnapshot.sessionId)
        let fixSessionState = CodeReviewSessionState(
            sessionId: fixSessionId,
            conversationId: conversationId ?? sourceSnapshot.conversationId,
            config: sessionConfig,
            onStateChange: { [weak self] snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self?.taskActivityStore.ingestCodeReviewSnapshot(
                        snapshot,
                        conversationId: self?.conversationId ?? snapshot.conversationId
                    )
                    self?.panelSessionId = snapshot.sessionId
                }
            }
        )

        guard let provider = ProviderFactory.codeReviewMultiSwarmProvider(
            config: cfg,
            executionController: executionController,
            agentProviderId: effectivePanelProviderId,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths,
            sessionState: fixSessionState,
            initialSessionConfig: sessionConfig
        ) else {
            return false
        }

        await ReviewSessionRegistry.shared.register(fixSessionState)
        taskActivityStore.ingestCodeReviewSnapshot(
            await fixSessionState.snapshot(),
            conversationId: conversationId ?? sourceSnapshot.conversationId
        )

        let prompt = CodeReviewPromptBuilder.targetedFixPrompt(
            snapshot: sourceSnapshot,
            findings: findings,
            targetSessionId: fixSessionId
        )
        let outputMessageId = beginPanelActionOutput(
            title: "Apply Fix (\(findings.count))",
            detail: prompt,
            selectChatTab: true
        )
        appendReviewRunSectionLine(
            id: outputMessageId,
            sectionTitle: "Activity",
            line: "Preparing targeted fix run..."
        )

        panelSessionId = fixSessionId
        taskActivityStore.setSelectedCodeReviewSessionId(fixSessionId, for: conversationId)
        isRunning = true
        runStartedAt = Date()
        frozenTimerText = nil
        lastError = nil

        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: buildWorkspaceContext(),
            sessionState: fixSessionState,
            onEvent: { [weak self] event in
                self?.streamPanelActionOutput(id: outputMessageId, event: event)
            },
            onStart: { [weak self] in
                self?.selectedTab = .chat
            },
            onComplete: { [weak self] _ in
                guard let self else { return }
                self.isRunning = false
                self.freezeTimer()
                self.finishPanelActionOutput(
                    id: outputMessageId,
                    fallbackContent: "Targeted fix completed."
                )
                Task { @MainActor in
                    for finding in findings {
                        await self.mutateSnapshot(
                            sessionId: sourceSnapshot.sessionId,
                            findingId: finding.id
                        ) { finding in
                            finding.status = .fixApplied
                        } event: {
                            .findingFixApplied(findingId: finding.id)
                        }
                    }
                    self.appendPanelSystemMessage(
                        "Applied targeted fix run for \(findings.count) finding(s).",
                        kind: .findingMutation,
                        selectChatTab: false
                    )
                }
            },
            onError: { [weak self] error in
                self?.isRunning = false
                self?.lastError = error
                self?.freezeTimer()
                self?.failPanelActionOutput(id: outputMessageId, error: error)
            }
        )
        return true
    }

    private func makePanelTargetedFixSessionId(sourceSessionId: String) -> String {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        let candidate = "\(sourceSessionId)-fix-\(suffix)"
        if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(candidate) {
            return sanitized
        }
        return UUID().uuidString.lowercased()
    }
}
