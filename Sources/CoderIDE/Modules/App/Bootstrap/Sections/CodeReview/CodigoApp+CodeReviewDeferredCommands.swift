import CoderEngine
import Foundation

struct CodeReviewCommandOutcome {
    let success: Bool
    let message: String
    let deferred: Bool

    static func immediate(success: Bool, message: String) -> Self {
        Self(success: success, message: message, deferred: false)
    }

    static func deferred(message: String) -> Self {
        Self(success: true, message: message, deferred: true)
    }
}

extension CodigoApp {
    @MainActor
    func launchDeferredReviewCommand(
        command: MCPSharedCodeReviewCommand,
        provider: any LLMProvider,
        sessionState: CodeReviewSessionState,
        prompt: String,
        context: WorkspaceContext,
        onSuccess: (@MainActor () async -> Bool)? = nil
    ) {
        Task { @MainActor in
            let heartbeat = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { break }
                    MCPSharedState.refreshCodeReviewCommandHeartbeat(id: command.id)
                }
            }
            defer { heartbeat.cancel() }
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await _ in stream {}

                let snapshot = await sessionState.snapshot()
                guard snapshot.phase == .completed else {
                    let failureMessage = snapshot.lastError
                        ?? "Code review session \(snapshot.sessionId) did not complete successfully"
                    MCPSharedState.markCodeReviewCommand(
                        id: command.id,
                        status: .failed,
                        resultMessage: failureMessage
                    )
                    return
                }

                if let onSuccess {
                    let succeeded = await onSuccess()
                    guard succeeded else {
                        MCPSharedState.markCodeReviewCommand(
                            id: command.id,
                            status: .failed,
                            resultMessage: "Code review completed, but the source finding state could not be updated"
                        )
                        return
                    }
                }

                MCPSharedState.markCodeReviewCommand(
                    id: command.id,
                    status: .completed,
                    resultMessage: "Code review session \(snapshot.sessionId) completed"
                )
            } catch {
                await sessionState.fail(error: error.localizedDescription)
                MCPSharedState.markCodeReviewCommand(
                    id: command.id,
                    status: .failed,
                    resultMessage: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    func makeCommandReviewSessionState(
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionState {
        CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: config,
            onStateChange: { snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self.taskActivityStore.ingestCodeReviewSnapshot(
                        snapshot,
                        conversationId: conversationId
                    )
                }
            }
        )
    }

    @MainActor
    func codeReviewCommandContext() -> WorkspaceContext {
        CodeReviewCommandRuntimeHooks.workspaceContext(for: self)
    }

    @MainActor
    func resolveCodeReviewSnapshot(
        sessionId: String,
        conversationId: UUID?
    ) -> CodeReviewSessionSnapshot? {
        let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) ?? MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId)
        guard let snapshot else { return nil }
        guard conversationId == nil || snapshot.conversationId == conversationId else {
            return nil
        }
        return snapshot
    }

    @MainActor
    func makeTargetedFixSessionId(sourceSessionId: String) -> String {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        let candidate = "\(sourceSessionId)-fix-\(suffix)"
        if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(candidate) {
            return sanitized
        }
        return UUID().uuidString.lowercased()
    }

    @MainActor
    func markFindingFixApplied(
        sessionId: String,
        conversationId: UUID?,
        findingId: String
    ) async -> Bool {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let succeeded = await liveState.applyFix(findingId: findingId)
            if succeeded {
                await persistLiveReviewState(
                    liveState,
                    conversationId: conversationId
                )
            }
            return succeeded
        }

        let result = await persistReviewSnapshotMutation(
            sessionId: sessionId,
            conversationId: conversationId
        ) { snapshot in
            var findings = snapshot.findings
            guard let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            findings[index].status = .fixApplied
            return CodeReviewSessionSnapshot(
                sessionId: snapshot.sessionId,
                conversationId: snapshot.conversationId,
                mutationSequence: snapshot.mutationSequence + 1,
                phase: snapshot.phase,
                stage: snapshot.stage,
                findings: findings,
                events: snapshot.events + [
                    .findingFixApplied(findingId: findingId)
                ],
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
        }
        return result.success
    }
}
