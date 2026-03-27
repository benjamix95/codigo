import Foundation

extension VerifiedFindingsSessionSyncService {
    private static let localSyncFindingThreshold = 256
    private static let localSyncTraceThreshold = 128

    static func syncVerifiedFindings(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> ReviewCoreVerifiedSyncResponse? {
        if shouldPreferLocalVerifiedSync(findings: findings, traceLog: traceLog) {
            return localVerifiedSyncResponse(findings: findings, traceLog: traceLog)
        }

        return syncWithRustBridge(findings: findings, traceLog: traceLog)
            ?? localVerifiedSyncResponse(findings: findings, traceLog: traceLog)
    }

    private static func shouldPreferLocalVerifiedSync(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["SOLOCODE_REVIEW_CORE_FORCE_RUST_SYNC"] == "1" {
            return false
        }
        if !ReviewCoreBridge.isEnabled {
            return true
        }
        return findings.count <= localSyncFindingThreshold
            && traceLog.count <= localSyncTraceThreshold
    }

    private static func syncWithRustBridge(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> ReviewCoreVerifiedSyncResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_sync_verified_findings",
            request: ReviewCoreVerifiedSyncRequest(
                schemaVersion: 1,
                findings: findings,
                traceLog: traceLog
            )
        )
    }

    private static func localVerifiedSyncResponse(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> ReviewCoreVerifiedSyncResponse {
        let identifiedFindings = applyIdentityPolicy(to: findings)
        let projection = VerifiedFindingsProjectionLocalBuilder.build(
            from: VerifiedFindingsCanonicalSnapshot(
                runs: [:],
                findings: Dictionary(uniqueKeysWithValues: identifiedFindings.map { ($0.id, $0) }),
                evidences: [:],
                verificationReports: [:],
                patchArtifacts: [:],
                revalidationReports: [:],
                commandLog: [],
                eventLog: [],
                traceLog: traceLog
            )
        )
        return ReviewCoreVerifiedSyncResponse(
            findings: identifiedFindings,
            projection: projection
        )
    }
}
