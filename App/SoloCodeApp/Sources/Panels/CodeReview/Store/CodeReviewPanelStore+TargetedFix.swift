import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func launchTargetedFixRun(
        sourceSnapshot: CodeReviewSessionSnapshot,
        findings: [CodeReviewFinding]
    ) async -> Bool {
        guard executionController != nil else { return false }
        guard let plan = planPanelTargetedFixLaunch(sourceSnapshot: sourceSnapshot) else {
            return false
        }
        let sessionConfig = plan.config
        let fixSessionId = plan.sessionId
        let runConversationId = panelRunConversationId(
            sourceConversationId: sourceSnapshot.conversationId
        )
        let fixSessionState = makePanelReviewSessionState(
            sessionId: fixSessionId,
            conversationId: runConversationId,
            config: sessionConfig
        )

        guard let provider = makePanelReviewProvider(
            sessionState: fixSessionState,
            sessionConfig: sessionConfig
        ) else {
            return false
        }

        await ReviewSessionRegistry.shared.register(fixSessionState)
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            await fixSessionState.snapshot(),
            conversationId: runConversationId
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

        runPanelReview(
            provider: provider,
            prompt: prompt,
            context: buildWorkspaceContext(),
            sessionState: fixSessionState,
            sessionId: fixSessionId,
            conversationId: conversationId,
            selectedTabOnStart: .chat,
            selectedTabOnFinish: .chat,
            onEvent: { [weak self] event in
                self?.streamPanelActionOutput(id: outputMessageId, event: event)
            },
            onComplete: { [weak self] _ in
                guard let self else { return }
                self.finishPanelActionOutput(
                    id: outputMessageId,
                    fallbackContent: "Targeted fix completed."
                )
                Task { @MainActor in
                    for finding in findings {
                        await self.mutateSnapshotUsingRust(
                            sessionId: sourceSnapshot.sessionId,
                            action: "apply_fix",
                            payload: ["finding_id": finding.id]
                        )
                    }
                    self.appendPanelSystemMessage(
                        "Applied targeted fix run for \(findings.count) finding(s).",
                        kind: .findingMutation,
                        selectChatTab: false
                    )
                }
            },
            onError: { [weak self] error in
                self?.failPanelActionOutput(id: outputMessageId, error: error)
            }
        )
        return true
    }
}
