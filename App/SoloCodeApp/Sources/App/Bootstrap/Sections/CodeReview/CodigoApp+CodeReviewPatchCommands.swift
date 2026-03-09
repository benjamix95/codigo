import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func handlePatchWorkflowCommand(
        _ command: MCPSharedCodeReviewCommand
    ) async -> CodeReviewCommandOutcome {
        guard let sessionId = command.sessionId,
              let findingId = command.payload["finding_id"] else {
            return .immediate(success: false, message: "Missing session_id or finding_id")
        }
        let conversationId = command.conversationId.flatMap(UUID.init(uuidString:))
        guard let snapshot = resolveCodeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return .immediate(success: false, message: "Review session not found")
        }
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return .immediate(success: false, message: "No active workspace is available for code review")
        }

        do {
            let synchronizedSnapshot = synchronizedVerifiedFindingsSnapshot(
                snapshot,
                conversationId: snapshot.conversationId
            )
            let meta = verifiedCommandMeta(
                for: command,
                entityId: findingId,
                snapshot: synchronizedSnapshot
            )
            let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                meta: meta,
                successSummary: "\(command.action) \(findingId)",
                currentEntityVersion: { [self] in
                    await currentVerifiedEntityVersion(
                        sessionId: sessionId,
                        conversationId: conversationId,
                        entityId: findingId
                    )
                }
            ) {
                let updated = try await self.executePatchWorkflowCommand(
                    command: command,
                    snapshot: snapshot,
                    findingId: findingId,
                    workspaceRoot: workspaceRoot
                )
                let synchronized = self.synchronizedVerifiedFindingsSnapshot(
                    updated,
                    conversationId: updated.conversationId
                )
                MCPSharedState.writeCodeReviewSnapshot(synchronized)
                await ReviewSessionRegistry.shared.recordSnapshot(synchronized)
                await MainActor.run {
                    taskActivityStore.ingestCodeReviewSnapshot(
                        synchronized,
                        conversationId: synchronized.conversationId
                    )
                }
            }
            switch outcome {
            case .executed(let summary), .deduplicated(let summary):
                return .immediate(success: true, message: summary)
            }
        } catch {
            return .immediate(success: false, message: error.localizedDescription)
        }
    }

    @MainActor
    private func executePatchWorkflowCommand(
        command: MCPSharedCodeReviewCommand,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String
    ) async throws -> CodeReviewSessionSnapshot {
        switch command.action {
        case "verify_finding":
            return try verifyFinding(snapshot: snapshot, findingId: findingId, workspaceRoot: workspaceRoot)
        default:
            return try await VerifiedFindingsPatchExecutionService.execute(
                action: command.action,
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: providerRegistry.selectedProviderId,
                providerRegistry: providerRegistry
            )
        }
    }

    private func verifyFinding(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String
    ) throws -> CodeReviewSessionSnapshot {
        let workspaceURL = URL(fileURLWithPath: workspaceRoot)
        let scopeFiles = Set((snapshot.scope?.files ?? []).map {
            $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0
        })

        var candidates = snapshot.candidates
        if let index = candidates.firstIndex(where: { $0.id == findingId }) {
            let result = ReviewCandidateVerificationService.verify(
                candidate: candidates[index],
                workspacePath: workspaceURL,
                scopeFiles: scopeFiles
            )
            candidates[index].verificationStatus = result.status
            candidates[index].verificationMethod = result.method
            candidates[index].verificationReport = result.report
            candidates[index].falsePositiveReason = result.falsePositiveReason
            candidates[index].verifiedAt = result.status == .verified ? Date() : nil
            var findings = snapshot.findings
            if result.status == .verified && !findings.contains(where: { $0.id == findingId }) {
                findings.append(.fromCandidate(candidates[index]))
            }
            return snapshot.copying(
                findings: findings,
                candidates: candidates,
                events: snapshot.events + [
                    result.status == .verified
                        ? .candidateVerified(candidateId: findingId)
                        : .candidateRejected(candidateId: findingId, reason: result.falsePositiveReason ?? result.status.rawValue),
                ],
                outcome: snapshot.copying(findings: findings, candidates: candidates).buildOutcomeSummary()
            )
        }
        return snapshot
    }

}
