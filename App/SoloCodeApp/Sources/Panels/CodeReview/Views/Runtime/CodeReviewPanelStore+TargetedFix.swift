import CoderEngine
import Foundation

@MainActor
struct ReviewPanelLaunchRequest: Equatable {
    let conversationId: UUID?
    let scope: ReviewScopeTarget
    let modes: Set<CodeReviewPanelMode>
    let reviewScanDepth: ReviewScanDepth
    let promptOverride: String
    let invocationLabel: String
}

@MainActor
final class ReviewPanelLaunchRequestStore {
    static let shared = ReviewPanelLaunchRequestStore()

    private var pendingQueuesByConversationKey: [String: [ReviewPanelLaunchRequest]] = [:]

    private init() {}

    func enqueue(_ request: ReviewPanelLaunchRequest) {
        let key = conversationKey(for: request.conversationId)
        var queue = pendingQueuesByConversationKey[key] ?? []
        queue.append(request)
        pendingQueuesByConversationKey[key] = queue
    }

    func consume(conversationId: UUID?) -> ReviewPanelLaunchRequest? {
        let key = conversationKey(for: conversationId)
        guard var queue = pendingQueuesByConversationKey[key], !queue.isEmpty else {
            return nil
        }
        let first = queue.removeFirst()
        if queue.isEmpty {
            pendingQueuesByConversationKey.removeValue(forKey: key)
        } else {
            pendingQueuesByConversationKey[key] = queue
        }
        return first
    }

    private func conversationKey(for conversationId: UUID?) -> String {
        conversationId?.uuidString.lowercased() ?? "workspace-review-panel"
    }
}

extension CodeReviewPanelStore {
    func rerunSession(_ sessionId: String) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId, conversationId: conversationId
        ) else { return }
        await startReview(scope: rerunScopeTarget(for: snapshot), modes: selectedModes)
    }

    func runQuickCommand(_ command: ReviewPanelSlashCommand) async {
        await startReview(
            scope: scopeTarget,
            modes: selectedModes,
            promptOverride: command.prompt,
            invocationLabel: command.displayCommand
        )
    }

    func planPanelReviewLaunch() -> (sessionId: String, config: SessionConfig)? {
        let selectedBackend = selectedProviderOverrideId ?? ""
        let resolvedAnalysisBackend = selectedBackend.isEmpty ? settings.analysisBackend : selectedBackend
        let resolvedExecutionBackend = selectedBackend.isEmpty ? settings.executionBackend : selectedBackend
        return planPanelLaunch(
            sessionPrefix: panelSessionPrefix,
            config: SessionConfig(
                maxWorkers: settings.maxWorkers,
                maxRounds: settings.maxRounds,
                analysisBackend: resolvedAnalysisBackend,
                executionBackend: resolvedExecutionBackend,
                analysisOnly: settings.analysisOnly
            )
        )
    }

    func planPanelTargetedFixLaunch(
        sourceSnapshot: CodeReviewSessionSnapshot
    ) -> (sessionId: String, config: SessionConfig)? {
        planPanelLaunch(
            sessionPrefix: "\(sourceSnapshot.sessionId)-fix",
            config: sourceSnapshot.config
        )
    }

    var panelSessionPrefix: String {
        if selectedModes == [.standard] || selectedModes.isEmpty {
            return "panel"
        }
        return primarySelectedMode.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    func rerunScopeTarget(for snapshot: CodeReviewSessionSnapshot) -> ReviewScopeTarget {
        switch snapshot.scope?.type {
        case .againstRef:
            return .againstRef(snapshot.scope?.ref ?? "HEAD~1")
        case .staged:
            return .staged
        case .workspace:
            return .workspace
        case .codebase:
            return .codebase
        case .uncommitted, .none:
            return .uncommitted
        }
    }

    func buildPrompt(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>
    ) async -> String {
        let paths = await gatherCodebasePromptFilePaths(scope: scope, depth: reviewScanDepth)
        var bridgeModes = modes
        bridgeModes.insert(.standard)
        return ReviewPanelCoordinator.combinedPrompt(
            scope: scope,
            currentBranch: currentGitBranch,
            selectedModes: bridgeModes,
            customInstructions: settings.customInstructions,
            scanDepth: reviewScanDepth,
            codebaseFilePaths: paths
        )
    }

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
            detail: prompt
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
            selectedTabOnStart: .findings,
            selectedTabOnFinish: .findings,
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
                        kind: .findingMutation
                    )
                }
            },
            onError: { [weak self] error in
                self?.failPanelActionOutput(id: outputMessageId, error: error)
            }
        )
        return true
    }

    func reviewInvocationLabel(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>
    ) -> String {
        let label = [CodeReviewPanelMode.securityAudit, .bugFinder]
            .filter { modes.contains($0) }
            .map(\.displayName)
            .joined(separator: " + ")
        return "Run \(reviewScanDepth.displayName) · \(label) on \(scope.displayDescription)"
    }

    private func planPanelLaunch(
        sessionPrefix: String,
        config: SessionConfig
    ) -> (sessionId: String, config: SessionConfig)? {
        let response: ReviewPanelStartPlanResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_launch",
            request: ReviewPanelStartPlanRequest(
                schemaVersion: 1,
                action: "start",
                sessionId: nil,
                payload: [
                    "max_workers": "\(config.maxWorkers)",
                    "max_rounds": "\(config.maxRounds)",
                    "analysis_backend": config.analysisBackend,
                    "execution_backend": config.executionBackend,
                    "analysis_only": config.analysisOnly ? "true" : "false",
                    "session_prefix": sessionPrefix,
                ],
                workspaceAvailable: !workspaceStore.activeWorkspacePaths.isEmpty,
                snapshotExists: false,
                currentConfig: nil,
                defaultConfig: ReviewPanelStartPlanConfig(
                    maxWorkers: config.maxWorkers,
                    maxRounds: config.maxRounds,
                    analysisBackend: config.analysisBackend,
                    executionBackend: config.executionBackend,
                    analysisOnly: config.analysisOnly
                )
            )
        )

        guard let response,
              !response.isError,
              let sessionId = response.sessionId,
              let config = response.config else {
            return nil
        }
        return (
            sessionId,
            SessionConfig(
                maxWorkers: config.maxWorkers,
                maxRounds: config.maxRounds,
                analysisBackend: config.analysisBackend,
                executionBackend: config.executionBackend,
                analysisOnly: config.analysisOnly
            )
        )
    }
}

private struct ReviewPanelStartPlanRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let sessionId: String?
    let payload: [String: String]
    let workspaceAvailable: Bool
    let snapshotExists: Bool
    let currentConfig: ReviewPanelStartPlanConfig?
    let defaultConfig: ReviewPanelStartPlanConfig
}

private struct ReviewPanelStartPlanConfig: Codable {
    let maxWorkers: Int
    let maxRounds: Int
    let analysisBackend: String
    let executionBackend: String
    let analysisOnly: Bool
}

private struct ReviewPanelStartPlanResponse: Decodable {
    let isError: Bool
    let sessionId: String?
    let config: ReviewPanelStartPlanConfig?
}
