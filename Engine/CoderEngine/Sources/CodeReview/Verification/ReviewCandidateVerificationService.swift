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
