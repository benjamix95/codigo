import Foundation

public struct ReviewCandidateVerificationResult: Sendable, Equatable {
    public let status: ReviewCandidateStatus
    public let method: String
    public let report: String
    public let falsePositiveReason: String?

    public init(
        status: ReviewCandidateStatus,
        method: String,
        report: String,
        falsePositiveReason: String? = nil
    ) {
        self.status = status
        self.method = method
        self.report = report
        self.falsePositiveReason = falsePositiveReason
    }
}

public enum ReviewCandidateVerificationService {
    public static func verify(
        candidate: ReviewCandidate,
        workspacePath: URL,
        scopeFiles: Set<String>
    ) -> ReviewCandidateVerificationResult {
        if let bridged = verifyWithRust(
            candidate: candidate,
            workspacePath: workspacePath,
            scopeFiles: scopeFiles
        ) {
            return bridged
        }
        return ReviewCandidateVerificationResult(
            status: .inconclusive,
            method: "rust_core_unavailable",
            report: "La verifica automatica richiede il review core Rust. Nessun fallback Swift locale è consentito."
        )
    }

    public static func candidate(
        from finding: CodeReviewFinding,
        signalType: ReviewSignalType
    ) -> ReviewCandidate {
        ReviewCandidate(
            id: finding.id,
            severity: finding.severity,
            category: finding.category,
            origin: finding.origin,
            filePath: finding.filePath,
            lineNumber: finding.lineNumber,
            endLineNumber: finding.endLineNumber,
            message: finding.message,
            evidence: finding.evidence,
            expectedInvariant: finding.expectedInvariant ?? finding.verificationReport,
            reproOrReasoning: finding.reproOrReasoning ?? finding.suggestedFix,
            confidence: finding.confidence,
            sourceTool: finding.sourceTool,
            signalType: signalType
        )
    }

    private static func verifyWithRust(
        candidate: ReviewCandidate,
        workspacePath: URL,
        scopeFiles: Set<String>
    ) -> ReviewCandidateVerificationResult? {
        let request = ReviewCoreVerifyCandidatesRequest(
            schemaVersion: 1,
            candidates: [candidate],
            workspacePath: workspacePath.path,
            scopeFiles: Array(scopeFiles).sorted()
        )
        let response: ReviewCoreVerifyCandidatesResponse? = ReviewCoreBridge.call(
            functionName: "review_core_verify_candidates",
            request: request
        )
        guard let result = response?.results?.first(where: { $0.candidateId == candidate.id }) else {
            return nil
        }
        return ReviewCandidateVerificationResult(
            status: ReviewCandidateStatus(rawValue: result.status) ?? .inconclusive,
            method: result.method,
            report: result.report,
            falsePositiveReason: result.falsePositiveReason
        )
    }
}

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

private struct ReviewCoreVerifyCandidatesRequest: Encodable {
    let schemaVersion: Int
    let candidates: [ReviewCandidate]
    let workspacePath: String
    let scopeFiles: [String]
}

private struct ReviewCoreVerifyCandidatesResponse: Decodable {
    let results: [ReviewCoreVerifyCandidateResult]?
}

private struct ReviewCoreVerifyCandidateResult: Decodable {
    let candidateId: String
    let status: String
    let method: String
    let report: String
    let falsePositiveReason: String?
}
