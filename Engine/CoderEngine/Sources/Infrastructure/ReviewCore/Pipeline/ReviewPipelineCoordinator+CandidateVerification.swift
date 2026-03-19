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
    ) -> ReviewCandidate? {
        let request = ReviewCoreCandidateFromFindingRequest(
            schemaVersion: 1,
            finding: finding,
            signalType: signalType
        )
        let response: ReviewCoreCandidateResponse? = ReviewCoreBridge.call(
            functionName: "review_core_candidate_from_finding",
            request: request
        )
        guard response?.error == nil else { return nil }
        return response?.candidate
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

    func reviewCandidate(from task: CodeReviewMultiSwarmProvider.ReviewTask, prefix: String) -> ReviewCandidate? {
        let request = ReviewCoreCandidateFromTaskRequest(
            schemaVersion: 1,
            task: task,
            prefix: prefix
        )
        let response: ReviewCoreCandidateResponse? = ReviewCoreBridge.call(
            functionName: "review_core_candidate_from_review_task",
            request: request
        )
        guard response?.error == nil else { return nil }
        return response?.candidate
    }

    private func normalizedReviewPath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value
    }
}

private struct ReviewCoreCandidateFromFindingRequest: Encodable {
    let schemaVersion: Int
    let finding: CodeReviewFinding
    let signalType: ReviewSignalType
}

private struct ReviewCoreCandidateFromTaskRequest: Encodable {
    let schemaVersion: Int
    let task: CodeReviewMultiSwarmProvider.ReviewTask
    let prefix: String
}

private struct ReviewCoreCandidateResponse: Decodable {
    let error: ReviewCoreCandidateError?
    let candidate: ReviewCandidate?
}

private struct ReviewCoreCandidateError: Decodable {
    let code: String
    let message: String
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
