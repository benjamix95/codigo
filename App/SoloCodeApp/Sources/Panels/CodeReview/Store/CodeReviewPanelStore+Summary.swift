import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func exportSummary(sessionId: String) -> String {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return "No session found" }
        return ReviewPanelChatMessageFactory.summary(snapshot: snapshot).content
    }

    func publishSummaryToChat(sessionId: String) {
        guard settings.publishOutcomeToChat else { return }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }
        selectTab(.chat)
        appendChatMessage(ReviewPanelChatMessageFactory.summary(snapshot: snapshot))
    }

    var currentPipelineJobState: ReviewPipelineJobState? {
        guard let snapshot = currentSnapshot else { return nil }
        return ReviewPipelineJobStateBuilder.build(snapshot: snapshot)
    }

    var currentPublishedFindings: [CodeReviewFinding] {
        guard let snapshot = currentSnapshot else { return [] }
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: .panel)
        let verifiedIds = Set(resolved.recovered.envelope.projectionSnapshot.verifiedQueue.map(\.id))
        let patchesByFindingId = Dictionary(uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) })

        return snapshot.findings.filter { finding in
            guard verifiedIds.contains(finding.id) else { return false }
            let isVerified = finding.verifiedAt != nil || finding.verificationReport != nil
            guard isVerified,
                  let patchId = finding.patchArtifactId,
                  let patch = patchesByFindingId[finding.id],
                  patch.id == patchId else {
                return false
            }
            return patch.verifyStatus == .verified
                && [.verified, .applied, .prOpened, .merged].contains(patch.status)
        }
    }
}

enum ReviewPipelineJobStateBuilder {
    static func build(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .panel
    ) -> ReviewPipelineJobState {
        let pipeline = VerifiedFindingsPipelineStatusService.evaluate(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        let bundleModes = pipeline.bundleModes.isEmpty ? ["standard", "bugFinder", "securityAudit"] : pipeline.bundleModes

        return ReviewPipelineJobState(
            title: "Unified Review Pipeline",
            phase: pipeline.pipelinePhase,
            progressPercent: pipeline.progressPercent,
            stepsCompleted: pipeline.stepsCompleted,
            stepsTotal: pipeline.stepsTotal,
            toolsTotal: pipeline.toolsTotal,
            toolsCompleted: pipeline.toolsCompleted,
            toolsRunning: pipeline.toolsRunning,
            candidateCount: pipeline.candidateCount,
            verifiedCount: pipeline.verifiedCount,
            publishedFindingCount: pipeline.publishedFindingCount,
            hiddenFindingCount: max(snapshot.findings.count - pipeline.publishedFindingCount, 0),
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: pipeline.verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: pipeline.patchGateReady),
            ],
            tools: toolExecutions(
                audit: snapshot.audit,
                pipeline: pipeline,
                bundleModes: bundleModes
            ),
            bundleModes: bundleModes,
            isTerminal: snapshot.phase == .completed || snapshot.phase == .failed
        )
    }

    private static func toolExecutions(
        audit: ReviewAuditSnapshot,
        pipeline: VerifiedFindingsPipelineStatus,
        bundleModes: [String]
    ) -> [ReviewPipelineToolExecution] {
        let auditedTools = audit.toolCoverage.keys.sorted().map { toolName in
            ReviewPipelineToolExecution(
                id: toolName,
                title: displayTitle(for: toolName),
                status: .completed,
                findingsCount: audit.toolFindingsCounts[toolName] ?? 0
            )
        }
        if !auditedTools.isEmpty {
            return auditedTools
        }

        return bundleModes.enumerated().map { index, mode in
            let runningThreshold = min(pipeline.toolsRunning, bundleModes.count)
            let status: ReviewPipelineToolExecution.Status
            if index < pipeline.toolsCompleted {
                status = .completed
            } else if index < pipeline.toolsCompleted + runningThreshold {
                status = .running
            } else {
                status = .pending
            }
            return ReviewPipelineToolExecution(
                id: mode,
                title: displayTitle(for: mode),
                status: status,
                findingsCount: 0
            )
        }
    }

    private static func displayTitle(for rawValue: String) -> String {
        switch rawValue {
        case "standard": return "Standard Review"
        case "bugFinder": return "Bug Finder"
        case "securityAudit": return "Security Audit"
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }
}
