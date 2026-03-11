import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func launchTargetedFixRun(
        sourceSnapshot: CodeReviewSessionSnapshot,
        findings: [CodeReviewFinding]
    ) async -> Bool {
        guard executionController != nil else { return false }
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
                    self?.taskActivityStore.scheduleCodeReviewSnapshotIngest(
                        snapshot,
                        conversationId: self?.conversationId ?? snapshot.conversationId
                    )
                    self?.schedulePanelSessionBinding(snapshot.sessionId)
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
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
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

    func makePanelTargetedFixSessionId(sourceSessionId: String) -> String {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        let candidate = "\(sourceSessionId)-fix-\(suffix)"
        if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(candidate) {
            return sanitized
        }
        return UUID().uuidString.lowercased()
    }
}
