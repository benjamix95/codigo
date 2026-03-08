import Foundation

extension ReviewPipelineCoordinator {
    func verifyCandidates(
        _ candidates: [ReviewCandidate],
        workspacePath: URL,
        filesToReview: [String],
        sessionState: CodeReviewSessionState
    ) async {
        let scopedFiles = Set(filesToReview.map(normalizedReviewPath))
        for candidate in candidates {
            let result = ReviewCandidateVerificationService.verify(
                candidate: candidate,
                workspacePath: workspacePath,
                scopeFiles: scopedFiles
            )
            _ = await sessionState.updateCandidateStatus(
                candidateId: candidate.id,
                status: result.status,
                method: result.method,
                report: result.report,
                falsePositiveReason: result.falsePositiveReason
            )
            if result.status == .verified {
                _ = await sessionState.promoteCandidateToFinding(candidateId: candidate.id)
            }
        }
    }

    func reviewCandidate(from task: CodeReviewMultiSwarmProvider.ReviewTask, prefix: String) -> ReviewCandidate {
        let finding = CodeReviewFinding.fromRawTask(
            id: "\(prefix)\(task.id)",
            description: task.description,
            files: task.files,
            severity: task.severity,
            category: task.category,
            origin: task.origin,
            filePath: task.files.first,
            lineNumber: task.lineNumber,
            confidence: task.confidence,
            evidence: task.evidence,
            sourceTool: task.sourceTool,
            blocking: task.blocking
        )
        return ReviewCandidate(
            id: finding.id,
            severity: finding.severity,
            category: finding.category,
            origin: task.origin,
            filePath: task.files.first ?? "unknown",
            lineNumber: task.lineNumber,
            endLineNumber: task.endLineNumber,
            message: task.description,
            evidence: task.evidence,
            expectedInvariant: task.expectedInvariant,
            reproOrReasoning: task.reproOrReasoning,
            confidence: task.confidence,
            sourceTool: task.sourceTool,
            signalType: task.origin == .auditTool ? .pattern : .semantic
        )
    }

    private func normalizedReviewPath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value
    }
}
