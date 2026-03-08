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
        let normalizedPath = normalizedRelativePath(candidate.filePath)
        if !scopeFiles.isEmpty && !scopeFiles.contains(normalizedPath) {
            return ReviewCandidateVerificationResult(
                status: .rejectedFalsePositive,
                method: "scope_guard",
                report: "Il file del candidate è fuori dallo scope corrente della review.",
                falsePositiveReason: "outside_review_scope"
            )
        }

        let absoluteURL = workspacePath.appendingPathComponent(normalizedPath)
        guard let content = try? String(contentsOf: absoluteURL, encoding: .utf8) else {
            return ReviewCandidateVerificationResult(
                status: .rejectedFalsePositive,
                method: "file_presence",
                report: "Il file associato al candidate non esiste più nel workspace.",
                falsePositiveReason: "file_missing"
            )
        }

        let lines = content.components(separatedBy: .newlines)
        guard let lineNumber = candidate.lineNumber, lineNumber > 0, lineNumber <= lines.count else {
            if let evidence = trimmedEvidence(candidate.evidence),
               content.localizedCaseInsensitiveContains(evidence) {
                return ReviewCandidateVerificationResult(
                    status: .verified,
                    method: "file_evidence_search",
                    report: "L'evidenza del candidate è stata trovata nel file \(normalizedPath)."
                )
            }
            return ReviewCandidateVerificationResult(
                status: .inconclusive,
                method: "missing_line_context",
                report: "Il candidate non ha un contesto di riga sufficiente per una verifica automatica affidabile."
            )
        }

        let lineText = lines[lineNumber - 1]
        if let evidence = trimmedEvidence(candidate.evidence),
           lineText.localizedCaseInsensitiveContains(evidence) {
            return ReviewCandidateVerificationResult(
                status: .verified,
                method: "line_evidence_match",
                report: "L'evidenza del candidate coincide con il contesto della riga \(lineNumber)."
            )
        }

        if matchesKnownRisk(message: candidate.message, line: lineText) {
            return ReviewCandidateVerificationResult(
                status: .verified,
                method: "semantic_risk_match",
                report: "Il contesto della riga \(lineNumber) conferma un pattern coerente con il rischio segnalato."
            )
        }

        return ReviewCandidateVerificationResult(
            status: .inconclusive,
            method: "context_mismatch",
            report: "Il candidate non è stato smentito, ma l'automazione non ha trovato prova sufficiente per promuoverlo a finding verificato."
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
            expectedInvariant: finding.verificationReport,
            reproOrReasoning: finding.suggestedFix,
            confidence: finding.confidence,
            sourceTool: finding.sourceTool,
            signalType: signalType
        )
    }

    private static func normalizedRelativePath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value
    }

    private static func trimmedEvidence(_ evidence: String?) -> String? {
        let trimmed = (evidence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func matchesKnownRisk(message: String, line: String) -> Bool {
        let lowerMessage = message.lowercased()
        let lowerLine = line.lowercased()
        let knownPairs: [(needle: String, tokens: [String])] = [
            ("fatal", ["fatalerror("]),
            ("force-try", ["try!"]),
            ("forced cast", [" as! "]),
            ("deadlock", ["dispatchqueue.main.sync"]),
            ("html injection", ["innerhtml"]),
            ("secret", ["api_key", "access_token", "client_secret", "ghp_", "sk_live_"]),
            ("http", ["http://"]),
        ]
        for pair in knownPairs where lowerMessage.contains(pair.needle) {
            if pair.tokens.contains(where: { lowerLine.contains($0) }) {
                return true
            }
        }
        return false
    }
}
