import Foundation

public struct VerifiedFindingsSecurityGateReport: Sendable, Codable, Equatable {
    public let ready: Bool
    public let canonicalProjectionMismatchCount: Int
    public let undetectedDuplicateCount: Int
    public let findingsMissingEvidenceCount: Int
    public let findingsMissingVerificationCount: Int
    public let rollbackCoverageCount: Int
    public let rollbackEligibleCount: Int
    public let applyRevalidateSuccessRate: Double
    public let knownCriticalRaceCount: Int
    public let summary: String
}

public enum SensitiveDataRedactionService {
    private static let patterns: [String] = [
        #"AKIA[0-9A-Z]{16}"#,
        #"ghp_[A-Za-z0-9]{20,}"#,
        #"sk_live_[A-Za-z0-9]{16,}"#,
        #"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9\-_\.]+"#,
        #"(?i)(token\s*=\s*)[^\s]+"#,
        #"(?i)(password\s*=\s*)[^\s]+"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
    ]

    public static func redact(_ raw: String) -> (value: String, wasRedacted: Bool) {
        var value = raw
        var changed = false
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let replaced = regex.stringByReplacingMatches(
                in: value,
                options: [],
                range: range,
                withTemplate: "$1[REDACTED]"
            )
            if replaced != value {
                value = replaced
                changed = true
            }
        }
        return (value, changed)
    }
}

public enum SecurityWorkflowService {
    private static let cacheLock = NSLock()
    private static var gateCache: [String: VerifiedFindingsSecurityGateReport] = [:]

    public static func evaluate(
        envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsSecurityGateReport {
        let cacheKey = [
            envelope.sessionId,
            String(envelope.lastUpdatedAt.timeIntervalSince1970),
            String(envelope.canonicalSnapshot.findings.count),
        ].joined(separator: "#")
        if let cached = cachedReport(for: cacheKey) {
            return cached
        }

        let report: VerifiedFindingsSecurityGateReport
        if shouldPreferRustGate, let bridged = evaluateWithRust(envelope: envelope) {
            report = bridged
        } else {
            report = evaluateLocally(envelope: envelope)
        }
        storeCachedReport(report, for: cacheKey)
        return report
    }

    private static func evaluateLocally(
        envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsSecurityGateReport {
        let canonical = envelope.canonicalSnapshot
        let rebuiltProjection = VerifiedFindingsProjectionLocalBuilder.build(from: canonical)
        let mismatchCount = rebuiltProjection == envelope.projectionSnapshot ? 0 : 1

        let findings = Array(canonical.findings.values)
        let verificationReportsByFinding = Dictionary(grouping: canonical.verificationReports.values, by: \.findingId)
        let evidencesByFinding = Dictionary(grouping: canonical.evidences.values, by: \.findingId)
        let undetectedDuplicateCount = countUndetectedDuplicates(findings)
        let findingsMissingEvidenceCount = findings.filter {
            guard $0.status == .verified || $0.status == .fixedVerified else { return false }
            return (evidencesByFinding[$0.id] ?? []).isEmpty
        }.count
        let findingsMissingVerificationCount = findings.filter {
            guard $0.status == .verified || $0.status == .fixedVerified else { return false }
            return (verificationReportsByFinding[$0.id] ?? []).isEmpty
        }.count

        let bugPatches = canonical.patchArtifacts.values.filter { patch in
            canonical.findings[patch.findingId]?.domain == .bug
        }
        let rollbackCoverageCount = bugPatches.filter(\.rollbackAvailable).count
        let rollbackEligibleCount = bugPatches.count
        let bugRevalidations = canonical.revalidationReports.values.filter { report in
            canonical.findings[report.findingId]?.domain == .bug
        }
        let successfulBugRevalidations = bugRevalidations.filter { $0.verdict == .fixedVerified }.count
        let applyRevalidateSuccessRate = bugRevalidations.isEmpty
            ? 1.0
            : Double(successfulBugRevalidations) / Double(bugRevalidations.count)

        let ready = mismatchCount == 0
            && undetectedDuplicateCount == 0
            && findingsMissingEvidenceCount == 0
            && findingsMissingVerificationCount == 0
            && (rollbackEligibleCount == 0 || rollbackCoverageCount == rollbackEligibleCount)
            && applyRevalidateSuccessRate >= 0.90

        return VerifiedFindingsSecurityGateReport(
            ready: ready,
            canonicalProjectionMismatchCount: mismatchCount,
            undetectedDuplicateCount: undetectedDuplicateCount,
            findingsMissingEvidenceCount: findingsMissingEvidenceCount,
            findingsMissingVerificationCount: findingsMissingVerificationCount,
            rollbackCoverageCount: rollbackCoverageCount,
            rollbackEligibleCount: rollbackEligibleCount,
            applyRevalidateSuccessRate: applyRevalidateSuccessRate,
            knownCriticalRaceCount: 0,
            summary: summary(
                ready: ready,
                mismatchCount: mismatchCount,
                undetectedDuplicateCount: undetectedDuplicateCount,
                findingsMissingEvidenceCount: findingsMissingEvidenceCount,
                findingsMissingVerificationCount: findingsMissingVerificationCount,
                rollbackCoverageCount: rollbackCoverageCount,
                rollbackEligibleCount: rollbackEligibleCount,
                applyRevalidateSuccessRate: applyRevalidateSuccessRate
            )
        )
    }

    private static var shouldPreferRustGate: Bool {
        ProcessInfo.processInfo.environment["SOLOCODE_REVIEW_CORE_USE_RUST_SECURITY_GATE"] == "1"
    }

    private static func cachedReport(for key: String) -> VerifiedFindingsSecurityGateReport? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return gateCache[key]
    }

    private static func storeCachedReport(
        _ report: VerifiedFindingsSecurityGateReport,
        for key: String
    ) {
        cacheLock.lock()
        gateCache[key] = report
        if gateCache.count > 64 {
            gateCache.removeValue(forKey: gateCache.keys.sorted().first ?? key)
        }
        cacheLock.unlock()
    }

    public static func makeStartRequest(
        args: [String: String],
        conversationId: UUID?
    ) throws -> VerifiedFindingsStartCommandRequest {
        var payload = args
        payload["review_prompt_override"] = securityReviewPrompt(from: args)
        payload["analysis_only"] = "true"
        payload["auto_prepare_verified_patches"] = "true"
        payload["auto_prepare_origin_filter"] = FindingOrigin.securityAuditor.rawValue
        return try VerifiedFindingsStartCommandService.makeRequest(
            args: payload,
            conversationId: conversationId
        )
    }

    public static func findings(
        snapshot: CodeReviewSessionSnapshot,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> [[String: String]] {
        VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: (kind ?? "verified").lowercased() == "candidate" ? .candidate : .verified,
                domain: .security,
                severity: severity,
                status: status,
                sourceOrigin: "securityAuditor",
                category: "security",
                file: file,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            ),
            entryPoint: entryPoint
        )
    }

    public static func gate(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsSecurityGateReport {
        VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint).securityGate
    }

    public static func currentGate(
        snapshots: [CodeReviewSessionSnapshot],
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsSecurityGateReport? {
        guard let snapshot = snapshots.first else { return nil }
        return gate(snapshot: snapshot, entryPoint: entryPoint)
    }

    public static func queueLifecycleCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        try VerifiedFindingsLifecycleCommandService.queueCommand(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        )
    }

    private static func securityReviewPrompt(from args: [String: String]) -> String {
        let scope = (args["scope"] ?? "uncommitted")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch scope {
        case "staged":
            return """
            [REVIEW_SCOPE:staged] [MODE:security-audit]
            Run a security-focused review on staged changes only.
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        case "against_ref":
            let ref = args["ref"] ?? "HEAD~1"
            return """
            [AGAINST:\(ref)] [MODE:security-audit]
            Run a security-focused review against ref \(ref).
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        default:
            return """
            [REVIEW_SCOPE:uncommitted] [MODE:security-audit]
            Run a security-focused review on uncommitted changes.
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        }
    }

    private static func evaluateWithRust(
        envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsSecurityGateReport? {
        let request = ReviewCoreSecurityGateRequest(
            schemaVersion: 1,
            envelope: envelope
        )
        let response: ReviewCoreSecurityGateBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_evaluate_security_gate",
            request: request
        )
        return response?.report
    }

    private static func countUndetectedDuplicates(_ findings: [VerifiedFinding]) -> Int {
        let grouped = Dictionary(grouping: findings, by: \.findingFingerprint)
        return grouped.values.reduce(0) { result, group in
            guard group.count > 1 else { return result }
            let unresolved = group.filter {
                $0.possibleDuplicateOf.isEmpty && $0.mergedIntoFindingId == nil && $0.recurrenceGroupId == nil
            }
            return result + unresolved.count
        }
    }

    private static func summary(
        ready: Bool,
        mismatchCount: Int,
        undetectedDuplicateCount: Int,
        findingsMissingEvidenceCount: Int,
        findingsMissingVerificationCount: Int,
        rollbackCoverageCount: Int,
        rollbackEligibleCount: Int,
        applyRevalidateSuccessRate: Double
    ) -> String {
        let readiness = ready ? "ready" : "blocked"
        let rate = String(format: "%.0f%%", applyRevalidateSuccessRate * 100)
        return "security_gate=\(readiness), mismatches=\(mismatchCount), undetected_duplicates=\(undetectedDuplicateCount), missing_evidence=\(findingsMissingEvidenceCount), missing_verification=\(findingsMissingVerificationCount), rollback=\(rollbackCoverageCount)/\(rollbackEligibleCount), apply_revalidate_success=\(rate)"
    }
}

private struct ReviewCoreSecurityGateRequest: Encodable {
    let schemaVersion: Int
    let envelope: VerifiedFindingsSessionEnvelope
}

private struct ReviewCoreSecurityGateBridgeResponse: Decodable {
    let report: VerifiedFindingsSecurityGateReport?
}

public enum VerifiedFindingsSecurityGateService {
    public static func evaluate(
        envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsSecurityGateReport {
        SecurityWorkflowService.evaluate(envelope: envelope)
    }
}
