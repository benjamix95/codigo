import Foundation

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
}
