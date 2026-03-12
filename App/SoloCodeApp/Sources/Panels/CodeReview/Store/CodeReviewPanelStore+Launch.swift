import CoderEngine
import Foundation

// MARK: - Review Execution

extension CodeReviewPanelStore {
    func consumePendingLaunchRequestIfNeeded() async {
        guard let request = ReviewPanelLaunchRequestStore.shared.consume(conversationId: conversationId) else {
            return
        }
        scopeTarget = request.scope
        selectedModes = request.modes
        selectTab(.findings)
        await startReview(
            scope: request.scope,
            modes: request.modes,
            promptOverride: request.promptOverride,
            invocationLabel: request.invocationLabel
        )
    }

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
        scopeTarget = scope
        selectedModes = modes
        selectTab(.findings)

        let sessionId = generateSessionId()
        let sessionConfig = buildSessionConfig()

        let sessionState = CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: sessionConfig,
            onStateChange: { [weak self] snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self?.taskActivityStore.scheduleCodeReviewSnapshotIngest(
                        snapshot,
                        conversationId: self?.conversationId
                    )
                    self?.schedulePanelSessionBinding(snapshot.sessionId)
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

        panelSessionId = sessionId
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)

        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            onEvent: { _ in },
            onStart: { [weak self] in
                self?.selectedTab = .findings
            },
            onComplete: { [weak self] snapshot in
                guard let self else { return }
                self.isRunning = false
                self.freezeTimer()
                if self.selectedTab != .chat {
                    self.selectedTab = .findings
                }
            },
            onError: { [weak self] error in
                self?.isRunning = false
                self?.lastError = error
                self?.freezeTimer()
                self?.selectedTab = .findings
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
        case .workspace:
            scope = .workspace
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
        await applyPatch(sessionId: sessionId, findingId: findingId)
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
            taskActivityStore.scheduleCodeReviewSnapshotIngest(
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
        await mutateSnapshotUsingRust(
            sessionId: sessionId,
            action: "dismiss",
            payload: [
                "finding_id": findingId,
                "reason": status == .wontFix ? FindingStatus.wontFix.rawValue : reason,
            ]
        )
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

        for finding in findings {
            await applyPatch(sessionId: sessionId, findingId: finding.id)
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

    func freezeTimer() {
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

}
